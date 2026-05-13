import CoreMedia
import Foundation
import Vision

/// Detects up to four human body poses per frame using Apple's
/// `VNDetectHumanBodyPoseRequest`.
///
/// No cross-frame tracking. Returns per-frame raw poses sorted by
/// confidence, capped at four. Milestone 6 touch attribution looks up
/// poses at single ball-detected frames so per-frame identity is enough;
/// proper tracking (IoU + Hungarian + Kalman) will land when we need
/// rally-scoped player IDs.
protocol PoseDetecting {
    func detect(in frame: PipelineFrame) async throws -> [PoseObservation]
}

final class PoseDetector: PoseDetecting {
    init(
        minObservationConfidence: Float = 0.4,
        minKeypointConfidence: Float = 0.1,
        maxPoses: Int = 4
    ) {
        self.minObservationConfidence = minObservationConfidence
        self.minKeypointConfidence = minKeypointConfidence
        self.maxPoses = maxPoses
    }

    private let minObservationConfidence: Float
    private let minKeypointConfidence: Float
    private let maxPoses: Int

    func detect(in frame: PipelineFrame) async throws -> [PoseObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = self.extractObservations(
                    request: request,
                    frame: frame
                )
                continuation.resume(returning: observations)
            }

            let handler = VNImageRequestHandler(
                cvPixelBuffer: frame.pixelBuffer,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func extractObservations(
        request: VNRequest,
        frame: PipelineFrame
    ) -> [PoseObservation] {
        guard let results = request.results as? [VNHumanBodyPoseObservation] else {
            return []
        }
        let width = CGFloat(CVPixelBufferGetWidth(frame.pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(frame.pixelBuffer))
        let timestampMs = Int(CMTimeGetSeconds(frame.presentationTime) * 1000)

        let candidates = results
            .filter { $0.confidence >= minObservationConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxPoses)

        return candidates.compactMap { observation -> PoseObservation? in
            guard let points = try? observation.recognizedPoints(.all) else {
                return nil
            }
            let validPoints = points.values.filter { $0.confidence > minKeypointConfidence }
            guard !validPoints.isEmpty else { return nil }

            // Vision normalises with origin at bottom-left; flip Y to image
            // coords with origin top-left, then scale to source pixels.
            let pixelPoints: [CGPoint] = validPoints.map { point in
                CGPoint(
                    x: point.location.x * width,
                    y: (1 - point.location.y) * height
                )
            }
            let xs = pixelPoints.map { $0.x }
            let ys = pixelPoints.map { $0.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            let bbox = CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )

            return PoseObservation(
                frameIndex: frame.frameIndex,
                timestampMs: timestampMs,
                keypoints: pixelPoints,
                boundingBox: bbox
            )
        }
    }
}
