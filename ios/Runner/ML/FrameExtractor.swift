import AVFoundation
import CoreMedia
import Foundation

/// Reads a video file from disk and invokes a callback for each sampled frame.
///
/// Stage 1 of the pipeline. Push-based with implicit back-pressure: the
/// extractor awaits the callback before pulling the next sample, so the
/// decoder never races ahead of downstream ML inference. (An earlier
/// AsyncStream version with `.bufferingOldest(2)` silently dropped frames
/// once detection slowed the consumer — that policy DROPS, it doesn't
/// back-pressure. The streaming abstraction was the wrong shape for this
/// pipeline.)
protocol FrameExtracting {
    /// Decodes the first video track of [videoURL] and invokes [onFrame]
    /// for each frame after stride sub-sampling. The call returns when the
    /// stream is exhausted or [onFrame] throws.
    func extractFrames(
        from videoURL: URL,
        config: PipelineRuntimeConfig,
        onFrame: (PipelineFrame) async throws -> Void
    ) async throws
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
        config: PipelineRuntimeConfig,
        onFrame: (PipelineFrame) async throws -> Void
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

            if rawIndex % stride == 0,
               let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                // Release the AVAssetReader pool slot ASAP. The
                // CVPixelBuffer is independently retained by the `let`.
                CMSampleBufferInvalidate(sample)

                let frame = PipelineFrame(
                    pixelBuffer: pixelBuffer,
                    presentationTime: pts,
                    frameIndex: emittedIndex
                )
                try await onFrame(frame)
                emittedIndex += 1
            } else {
                CMSampleBufferInvalidate(sample)
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
            return
        }
    }
}
