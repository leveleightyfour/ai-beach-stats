import Foundation

/// Groups ball detections into rally spans by detecting gaps in continuous
/// ball presence.
///
/// Heuristic v1:
/// - A rally is a span of consecutive frames in which the ball is detected
///   with no gap longer than `config.rallyGapThreshold`.
/// - Spans shorter than `config.minRallyDuration` are discarded as noise.
protocol RallySegmenting {
    func segment(
        detections: [BallDetection],
        config: PipelineRuntimeConfig
    ) -> [RallySpan]
}

final class RallySegmenter: RallySegmenting {
    func segment(
        detections: [BallDetection],
        config: PipelineRuntimeConfig
    ) -> [RallySpan] {
        // TODO(milestone-1): single-pass scan over detections, splitting on
        // gaps > rallyGapThreshold, filtering spans < minRallyDuration.
        return []
    }
}
