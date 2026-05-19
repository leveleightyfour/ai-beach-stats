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
    /// Stop tracking when Vision's confidence drops below this.
    /// Vision tracks degrade over time; default 0.3 is conservative.
    init(minConfidence: Float = 0.3, maxFramesPerSession: Int = 120) {
        self.minConfidence = minConfidence
        self.maxFramesPerSession = maxFramesPerSession
    }

    private let minConfidence: Float
    private let maxFramesPerSession: Int

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

        currentObservation = result
        sessionFrameCount += 1

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
}
