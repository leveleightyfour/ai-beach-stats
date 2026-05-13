import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import UIKit

/// Top-level orchestrator. As of milestone 6 it drives frame extraction,
/// ball detection, per-frame pose detection (only on ball-detected frames),
/// rally segmentation, and touch attribution. `PlayerTracker` remains a
/// stub — cross-frame player identity is not used yet.
protocol PipelineOrchestrating {
    /// Emits an `AsyncStream<PipelineEvent>` for the given session. The
    /// stream completes after the terminal event.
    func run(
        sessionId: String,
        matchId: String,
        videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> AsyncStream<PipelineEvent>
}

final class PipelineRunner: PipelineOrchestrating {
    init(
        frameExtractor: FrameExtracting,
        ballDetector: BallDetecting,
        poseDetector: PoseDetecting,
        playerTracker: PlayerTracking,
        rallySegmenter: RallySegmenting,
        touchAttributor: TouchAttributing,
        previewWriter: PreviewThumbnailWriting = PreviewThumbnailWriter()
    ) {
        self.frameExtractor = frameExtractor
        self.ballDetector = ballDetector
        self.poseDetector = poseDetector
        self.playerTracker = playerTracker
        self.rallySegmenter = rallySegmenter
        self.touchAttributor = touchAttributor
        self.previewWriter = previewWriter
    }

    private let frameExtractor: FrameExtracting
    private let ballDetector: BallDetecting
    private let poseDetector: PoseDetecting
    private let playerTracker: PlayerTracking
    private let rallySegmenter: RallySegmenting
    private let touchAttributor: TouchAttributing
    private let previewWriter: PreviewThumbnailWriting

    private static let progressEveryNFrames = 30

    func run(
        sessionId: String,
        matchId: String,
        videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> AsyncStream<PipelineEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let started = Date()
                let totalFrames = (try? await Self.estimateTotalFrames(
                    videoURL: videoURL,
                    config: config
                )) ?? 0

                var framesProcessed: Int64 = 0
                var ballDetectionsCount: Int64 = 0
                var detections: [BallDetection] = []
                var posesByFrame: [Int: [PoseObservation]] = [:]
                var frameWidth: Int64 = 0
                var frameHeight: Int64 = 0
                var previewPath: String? = nil

                do {
                    try Task.checkCancellation()

                    try await self.frameExtractor.extractFrames(
                        from: videoURL,
                        config: config
                    ) { frame in
                        try Task.checkCancellation()
                        framesProcessed += 1

                        if frame.frameIndex == 0 {
                            previewPath = try? self.previewWriter.writeFirstFrame(
                                frame: frame,
                                sessionId: sessionId
                            )
                            frameWidth = Int64(CVPixelBufferGetWidth(frame.pixelBuffer))
                            frameHeight = Int64(CVPixelBufferGetHeight(frame.pixelBuffer))
                        }

                        if let detection = try? await self.ballDetector.detect(in: frame) {
                            ballDetectionsCount += 1
                            detections.append(detection)

                            // Pose only runs on ball-detected frames — the
                            // touch attributor only consults poses at those
                            // frames, so this saves a lot of inference.
                            if let poses = try? await self.poseDetector.detect(in: frame),
                               !poses.isEmpty {
                                posesByFrame[frame.frameIndex] = poses
                            }
                        }

                        if frame.frameIndex == 0 ||
                            Int(framesProcessed) % Self.progressEveryNFrames == 0 {
                            let progress = PipelineProgress(
                                stage: .detectingBall,
                                fractionComplete: totalFrames > 0
                                    ? min(1.0, Double(framesProcessed) / Double(totalFrames))
                                    : 0.0,
                                framesProcessed: framesProcessed,
                                totalFrames: Int64(totalFrames),
                                ballDetectionsSoFar: ballDetectionsCount,
                                previewThumbnailPath: previewPath
                            )
                            continuation.yield(
                                PipelineEvent(
                                    sessionId: sessionId,
                                    type: .progress,
                                    progress: progress,
                                    result: nil,
                                    error: nil
                                )
                            )
                        }
                    }

                    // Brief progress signal that we're past the frame loop.
                    continuation.yield(
                        PipelineEvent(
                            sessionId: sessionId,
                            type: .progress,
                            progress: PipelineProgress(
                                stage: .finalising,
                                fractionComplete: 1.0,
                                framesProcessed: framesProcessed,
                                totalFrames: Int64(totalFrames),
                                ballDetectionsSoFar: ballDetectionsCount,
                                previewThumbnailPath: previewPath
                            ),
                            result: nil,
                            error: nil
                        )
                    )

                    let frameSize = CGSize(
                        width: Double(frameWidth),
                        height: Double(frameHeight)
                    )
                    let rallySpans = self.rallySegmenter.segment(
                        detections: detections,
                        config: config
                    )
                    let rallyResults = rallySpans.map { span -> RallyResult in
                        let touches = self.touchAttributor.attribute(
                            rally: span,
                            ballDetections: detections,
                            posesByFrame: posesByFrame,
                            config: config,
                            frameSize: frameSize
                        )
                        let rallyObservations = detections
                            .filter { detection in
                                detection.timestampMs >= span.startTimestampMs
                                    && detection.timestampMs <= span.endTimestampMs
                            }
                            .map(Self.toPigeon(_:))
                        var counts: [Int64] = [0, 0, 0, 0]
                        for touch in touches where (0..<4).contains(touch.playerSlotIndex) {
                            counts[touch.playerSlotIndex] += 1
                        }
                        let pigeonTouches = touches.map { touch -> TouchEvent in
                            TouchEvent(
                                timestampMs: Int64(touch.timestampMs),
                                playerSlot: PlayerSlot(rawValue: touch.playerSlotIndex)
                                    ?? .homeLeft,
                                ballX: Double(touch.ballPosition.x),
                                ballY: Double(touch.ballPosition.y)
                            )
                        }
                        return RallyResult(
                            rallyIndex: Int64(span.rallyIndex),
                            startTimestampMs: Int64(span.startTimestampMs),
                            endTimestampMs: Int64(span.endTimestampMs),
                            touchCountBySlot: counts,
                            touches: pigeonTouches,
                            ballObservations: rallyObservations
                        )
                    }

                    let elapsed = Int64(Date().timeIntervalSince(started) * 1000)
                    let result = PipelineResult(
                        matchId: matchId,
                        rallies: rallyResults,
                        ballObservations: detections.map(Self.toPigeon(_:)),
                        frameWidth: frameWidth,
                        frameHeight: frameHeight,
                        totalFramesProcessed: framesProcessed,
                        totalBallDetections: ballDetectionsCount,
                        totalDurationMs: elapsed
                    )
                    continuation.yield(
                        PipelineEvent(
                            sessionId: sessionId,
                            type: .completion,
                            progress: nil,
                            result: result,
                            error: nil
                        )
                    )
                } catch is CancellationError {
                    print("[PipelineRunner] cancelled sessionId=\(sessionId)")
                    continuation.yield(
                        PipelineEvent(
                            sessionId: sessionId,
                            type: .cancelled,
                            progress: nil,
                            result: nil,
                            error: nil
                        )
                    )
                } catch {
                    print("[PipelineRunner] ERROR sessionId=\(sessionId) error=\(error) localizedDescription=\(error.localizedDescription)")
                    let pipelineError = PipelineError(
                        code: "extraction_failed",
                        message: "\(type(of: error)): \(error.localizedDescription)"
                    )
                    continuation.yield(
                        PipelineEvent(
                            sessionId: sessionId,
                            type: .error,
                            progress: nil,
                            result: nil,
                            error: pipelineError
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func toPigeon(_ detection: BallDetection) -> BallObservation {
        BallObservation(
            frameIndex: Int64(detection.frameIndex),
            timestampMs: Int64(detection.timestampMs),
            x: Double(detection.boundingBox.origin.x),
            y: Double(detection.boundingBox.origin.y),
            width: Double(detection.boundingBox.size.width),
            height: Double(detection.boundingBox.size.height),
            confidence: detection.confidence
        )
    }

    private static func estimateTotalFrames(
        videoURL: URL,
        config: PipelineRuntimeConfig
    ) async throws -> Int {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let nominalRate = try await tracks.first?.load(.nominalFrameRate) ?? 30
        let sampledRate = min(Float(config.frameRateHz), nominalRate)
        return Int((Double(sampledRate) * durationSeconds).rounded())
    }
}

/// Writes a JPEG snapshot of a `PipelineFrame` to the documents directory
/// for use as a UI preview. Pulled behind a protocol so tests can stub it.
protocol PreviewThumbnailWriting {
    func writeFirstFrame(frame: PipelineFrame, sessionId: String) throws -> String
}

final class PreviewThumbnailWriter: PreviewThumbnailWriting {
    func writeFirstFrame(
        frame: PipelineFrame,
        sessionId: String
    ) throws -> String {
        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw NSError(
                domain: "PreviewThumbnailWriter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not render preview frame."]
            )
        }
        let uiImage = UIImage(cgImage: cgImage)
        guard let data = uiImage.jpegData(compressionQuality: 0.75) else {
            throw NSError(
                domain: "PreviewThumbnailWriter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "JPEG encoding failed."]
            )
        }

        let fm = FileManager.default
        let docs = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("sessions/\(sessionId)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("first_frame.jpg")
        try data.write(to: url, options: .atomic)
        return url.path
    }
}
