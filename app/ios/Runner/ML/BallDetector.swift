import CoreML
import Foundation
import Vision

/// Runs the ball-detection model against a single frame, returning at most
/// one best-confidence detection.
///
/// Initial implementation: a generic YOLO11n COCO model, filtered to the
/// `sports ball` class. The protocol is deliberately model-agnostic so the
/// production model can be swapped in without touching the rest of the
/// pipeline.
protocol BallDetecting {
    func detect(in frame: PipelineFrame) async throws -> BallDetection?
}

final class BallDetector: BallDetecting {
    init(confidenceThreshold: Double) {
        self.confidenceThreshold = confidenceThreshold
    }

    private let confidenceThreshold: Double

    func detect(in frame: PipelineFrame) async throws -> BallDetection? {
        // TODO(milestone-1): load CoreML model lazily and run a
        // VNCoreMLRequest, filtering for the sports-ball class.
        return nil
    }
}
