import Foundation
import Vision

/// Detects up to four human body poses per frame using Apple's
/// `VNDetectHumanBodyPoseRequest`.
protocol PoseDetecting {
    func detect(in frame: PipelineFrame) async throws -> [PoseObservation]
}

final class PoseDetector: PoseDetecting {
    func detect(in frame: PipelineFrame) async throws -> [PoseObservation] {
        // TODO(milestone-1): run VNDetectHumanBodyPoseRequest on the frame,
        // extract keypoints + bounding boxes, cap at top-4 confidence.
        return []
    }
}
