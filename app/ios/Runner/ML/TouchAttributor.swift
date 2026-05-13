import Foundation

/// Detects per-rally touch events and attributes each to a player slot.
///
/// Touch detection v1: a sharp change in ball trajectory direction AND a
/// player within `config.touchProximityPx` of the ball at that moment.
/// Slot attribution v1: map the tracked player's centroid into one of the
/// four court quadrants (home-left / home-right / away-left / away-right).
protocol TouchAttributing {
    func attribute(
        rally: RallySpan,
        ballDetections: [BallDetection],
        trackedPlayersByFrame: [Int: [TrackedPlayer]],
        config: PipelineRuntimeConfig
    ) -> [AttributedTouch]
}

final class TouchAttributor: TouchAttributing {
    func attribute(
        rally: RallySpan,
        ballDetections: [BallDetection],
        trackedPlayersByFrame: [Int: [TrackedPlayer]],
        config: PipelineRuntimeConfig
    ) -> [AttributedTouch] {
        // TODO(milestone-1): compute per-frame trajectory deltas, detect
        // direction changes above a threshold, find nearest player within
        // touchProximityPx, emit AttributedTouch.
        return []
    }
}
