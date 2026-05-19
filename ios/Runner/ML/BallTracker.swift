import CoreMedia
import Foundation
import Vision

/// Stateful ball tracker that fills gaps between detector hits.
///
/// Pipeline pattern:
/// 1. `BallDetector` finds the ball with confidence; runner calls
///    `startSession` anchored on that frame + bbox.
/// 2. Subsequent frames call `predict` to propagate the track. As long
///    as the tracker has confidence the runner uses tracker output as
///    the per-frame detection, skipping the detector.
/// 3. When the tracker loses the ball (`predict` returns nil) the
///    session ends automatically; runner falls back to `BallDetector`
///    until the next detection re-anchors a fresh session.
///
/// `VisionBallTracker` is the current implementation, using
/// `VNTrackObjectRequest`. Built into iOS so no model to bundle. A
/// `SAM2BallTracker` could be slotted in behind the same protocol
/// later for stronger tracking on occluded / motion-blurred play.
protocol BallTracking {
    var isAvailable: Bool { get }
    var isSessionActive: Bool { get }

    func startSession(
        initialFrame: PipelineFrame,
        initialDetection: BallDetection
    )

    func predict(in frame: PipelineFrame) async throws -> BallDetection?

    func endSession()
}

final class VisionBallTracker: BallTracking {
    /// Vision's tracker is correlation-based — it locks onto whatever
    /// is in its search window. On beach footage that means it drifts
    /// onto darker, more textured features (player heads, pants,
    /// shadows on sand) as soon as the ball moves out of the bbox.
    ///
    /// Mitigations applied here:
    /// - Short session cap so drift can't accumulate for long.
    /// - Higher confidence floor so Vision gives up faster.
    /// - Brightness sanity check on each predicted bbox: beach
    ///   volleyballs are very bright (luminance ~220-255); skin /
    ///   hair / dark sand patches are ~30-150. Reject bboxes whose
    ///   centre samples below the floor.
    init(
        minConfidence: Float = 0.4,
        maxFramesPerSession: Int = 30,
        minBrightness: Float = 150
    ) {
        self.minConfidence = minConfidence
        self.maxFramesPerSession = maxFramesPerSession
        self.minBrightness = minBrightness
    }

    private let minConfidence: Float
    private let maxFramesPerSession: Int
    private let minBrightness: Float

    private var sequenceHandler = VNSequenceRequestHandler()
    private var currentObservation: VNDetectedObjectObservation?
    private var sessionActive = false
    private var sessionFrameCount = 0

    var isAvailable: Bool { true }
    var isSessionActive: Bool { sessionActive }

    func startSession(
        initialFrame: PipelineFrame,
        initialDetection: BallDetection
    ) {
        let width = CGFloat(CVPixelBufferGetWidth(initialFrame.pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(initialFrame.pixelBuffer))
        guard width > 0, height > 0 else { return }

        // Vision uses normalised coords with origin bottom-left. Convert
        // from our source-pixel coords (top-left).
        let bbox = initialDetection.boundingBox
        let normalised = CGRect(
            x: bbox.origin.x / width,
            y: 1.0 - (bbox.origin.y + bbox.size.height) / height,
            width: bbox.size.width / width,
            height: bbox.size.height / height
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !normalised.isEmpty else { return }

        currentObservation = VNDetectedObjectObservation(boundingBox: normalised)
        sequenceHandler = VNSequenceRequestHandler()
        sessionActive = true
        sessionFrameCount = 0
        print("[VisionBallTracker] session started anchorFrame=\(initialFrame.frameIndex)")
    }

    func predict(in frame: PipelineFrame) async throws -> BallDetection? {
        guard sessionActive, let last = currentObservation else { return nil }

        if sessionFrameCount >= maxFramesPerSession {
            print("[VisionBallTracker] session capped at \(maxFramesPerSession) frames; ending")
            endSession()
            return nil
        }

        let request = VNTrackObjectRequest(detectedObjectObservation: last)
        request.trackingLevel = .accurate

        do {
            try sequenceHandler.perform([request], on: frame.pixelBuffer)
        } catch {
            print("[VisionBallTracker] perform failed: \(error). Ending session.")
            endSession()
            return nil
        }

        guard
            let result = request.results?.first as? VNDetectedObjectObservation
        else {
            endSession()
            return nil
        }

        if result.confidence < minConfidence {
            print("[VisionBallTracker] confidence \(result.confidence) < \(minConfidence) at frame \(frame.frameIndex); ending")
            endSession()
            return nil
        }

        // Convert back to source-pixel coords with top-left origin.
        let width = CGFloat(CVPixelBufferGetWidth(frame.pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(frame.pixelBuffer))
        let bbox = result.boundingBox
        let pixelRect = CGRect(
            x: bbox.origin.x * width,
            y: (1.0 - bbox.origin.y - bbox.size.height) * height,
            width: bbox.size.width * width,
            height: bbox.size.height * height
        )

        // Sanity check: if the tracked bbox no longer contains
        // ball-bright pixels, Vision has drifted onto something else.
        // End the session and let the detector reacquire on the next
        // frame.
        let brightness = Self.sampleBrightness(at: pixelRect, in: frame.pixelBuffer)
        if brightness < minBrightness {
            print("[VisionBallTracker] brightness \(Int(brightness)) < \(Int(minBrightness)) at frame \(frame.frameIndex); ending (likely drifted)")
            endSession()
            return nil
        }

        currentObservation = result
        sessionFrameCount += 1

        let timestampMs = Int(
            CMTimeGetSeconds(frame.presentationTime) * 1000
        )
        return BallDetection(
            frameIndex: frame.frameIndex,
            timestampMs: timestampMs,
            boundingBox: pixelRect,
            confidence: Double(result.confidence)
        )
    }

    func endSession() {
        if sessionActive {
            print("[VisionBallTracker] session ended after \(sessionFrameCount) frames")
        }
        sessionActive = false
        sessionFrameCount = 0
        currentObservation = nil
        sequenceHandler = VNSequenceRequestHandler()
    }

    /// Mean luminance of a 5×5 window at the centre of [rect] in [pixelBuffer].
    /// Uses standard Rec. 601 luma weights against BGRA pixel data
    /// (matches the format AVAssetReader writes for our pipeline).
    private static func sampleBrightness(
        at rect: CGRect,
        in pixelBuffer: CVPixelBuffer
    ) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let buf = base.assumingMemoryBound(to: UInt8.self)

        let cx = max(0, min(width - 1, Int(rect.midX.rounded())))
        let cy = max(0, min(height - 1, Int(rect.midY.rounded())))
        let radius = 2

        var sum = 0
        var count = 0
        for dy in -radius...radius {
            for dx in -radius...radius {
                let x = cx + dx
                let y = cy + dy
                if x < 0 || x >= width || y < 0 || y >= height { continue }
                let offset = y * bytesPerRow + x * 4
                let b = Int(buf[offset])
                let g = Int(buf[offset + 1])
                let r = Int(buf[offset + 2])
                // Rec. 601 luma, integer-scaled. Range: 0-255.
                let luma = (299 * r + 587 * g + 114 * b) / 1000
                sum += luma
                count += 1
            }
        }
        return count > 0 ? Float(sum) / Float(count) : 0
    }
}
