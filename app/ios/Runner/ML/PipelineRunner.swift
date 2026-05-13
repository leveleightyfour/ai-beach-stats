import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import UIKit

/// Top-level orchestrator. For milestone 4 it only drives the frame
/// extractor and emits progress / completion events — the remaining
/// stages (ball detection, pose, tracking, rally, touch) are stubs that
/// will be wired in later milestones.
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
                var ballDetections: Int64 = 0
                var previewPath: String? = nil

                do {
                    try Task.checkCancellation()

                    for try await frame in self.frameExtractor.extractFrames(
                        from: videoURL,
                        config: config
                    ) {
                        try Task.checkCancellation()
                        framesProcessed += 1

                        if frame.frameIndex == 0 {
                            previewPath = try? self.previewWriter.writeFirstFrame(
                                frame: frame,
                                sessionId: sessionId
                            )
                        }

                        if let _ = try? await self.ballDetector.detect(in: frame) {
                            ballDetections += 1
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
                                ballDetectionsSoFar: ballDetections,
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

                    let elapsed = Int64(Date().timeIntervalSince(started) * 1000)
                    let result = PipelineResult(
                        matchId: matchId,
                        rallies: [],
                        totalFramesProcessed: framesProcessed,
                        totalBallDetections: ballDetections,
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
                    let pipelineError = PipelineError(
                        code: "extraction_failed",
                        message: error.localizedDescription
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
