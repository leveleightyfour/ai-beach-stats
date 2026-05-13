import AVFoundation
import CoreMedia
import Foundation

/// Reads a video file from disk and emits sampled frames at the requested rate.
///
/// Stage 1 of the pipeline. Uses `AVAssetReader` against the first video
/// track of the asset. Frames are decoded as BGRA pixel buffers and
/// down-sampled to roughly `config.frameRateHz`.
protocol FrameExtracting {
    func extractFrames(
        from videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> AsyncThrowingStream<PipelineFrame, Error>
}

enum FrameExtractorError: LocalizedError {
    case missingVideoTrack
    case readerFailure(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "Video file does not contain a video track."
        case let .readerFailure(underlying):
            return "AVAssetReader failed: \(underlying?.localizedDescription ?? "unknown")"
        }
    }
}

final class FrameExtractor: FrameExtracting {
    func extractFrames(
        from videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> AsyncThrowingStream<PipelineFrame, Error> {
        // Bound the buffer so the decoder doesn't run ahead of the downstream
        // detector and pile up pixel buffers in memory.
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(2)) { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await self.run(
                        videoURL: videoURL,
                        config: config,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        videoURL: URL,
        config: PipelineRuntimeConfig,
        continuation: AsyncThrowingStream<PipelineFrame, Error>.Continuation
    ) async throws {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: videoURL.path)
        let size = (try? fm.attributesOfItem(atPath: videoURL.path)[.size]) as? Int ?? -1
        let readable = fm.isReadableFile(atPath: videoURL.path)
        print("[FrameExtractor] start path=\(videoURL.path) exists=\(exists) readable=\(readable) size=\(size)")

        let asset = AVURLAsset(url: videoURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        print("[FrameExtractor] tracks loaded count=\(tracks.count)")
        guard let track = tracks.first else {
            throw FrameExtractorError.missingVideoTrack
        }

        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let sourceRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0
        let targetRate = max(1, Float(config.frameRateHz))
        let stride = max(1, Int((sourceRate / targetRate).rounded()))
        print("[FrameExtractor] sourceRate=\(sourceRate) targetRate=\(targetRate) stride=\(stride)")

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw FrameExtractorError.readerFailure(underlying: nil)
        }
        reader.add(output)

        guard reader.startReading() else {
            throw FrameExtractorError.readerFailure(underlying: reader.error)
        }

        var rawIndex = 0
        var emittedIndex = 0
        var loopExitReason = "unknown"

        while reader.status == .reading {
            try Task.checkCancellation()

            guard let sample = output.copyNextSampleBuffer() else {
                loopExitReason = "copyNextSampleBuffer returned nil"
                break
            }

            defer { CMSampleBufferInvalidate(sample) }

            if rawIndex % stride == 0,
               let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let frame = PipelineFrame(
                    pixelBuffer: pixelBuffer,
                    presentationTime: pts,
                    frameIndex: emittedIndex
                )
                continuation.yield(frame)
                emittedIndex += 1
            }
            rawIndex += 1
        }
        if loopExitReason == "unknown" {
            loopExitReason = "reader.status != .reading (status=\(reader.status.rawValue))"
        }
        print("[FrameExtractor] loop ended raw=\(rawIndex) emitted=\(emittedIndex) reason=\(loopExitReason) finalStatus=\(reader.status.rawValue) error=\(String(describing: reader.error))")

        switch reader.status {
        case .failed:
            throw FrameExtractorError.readerFailure(underlying: reader.error)
        case .cancelled:
            throw CancellationError()
        default:
            continuation.finish()
        }
    }
}
