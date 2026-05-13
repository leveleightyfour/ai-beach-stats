import AVFoundation
import Foundation

/// Reads a video file from disk and emits sampled frames at the requested rate.
///
/// Stage 1 of the pipeline. Implementations should:
/// - Open the asset with `AVAssetReader` and a video output track.
/// - Sample frames at `config.frameRateHz` (drop or hold as needed).
/// - Emit `PipelineFrame` values in order, with monotonically increasing
///   `frameIndex` and `presentationTime`.
protocol FrameExtracting {
    /// Streams frames asynchronously. Cancellation is observed via
    /// `Task.checkCancellation()` between frames.
    func extractFrames(
        from videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> AsyncThrowingStream<PipelineFrame, Error>
}

final class FrameExtractor: FrameExtracting {
    func extractFrames(
        from videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> AsyncThrowingStream<PipelineFrame, Error> {
        // TODO(milestone-1): implement AVAssetReader-backed sampling loop.
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
