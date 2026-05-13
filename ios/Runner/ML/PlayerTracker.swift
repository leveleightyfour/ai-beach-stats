import Foundation

/// Maintains per-rally stable IDs for detected players using IoU matching
/// plus Hungarian assignment, with a small Kalman smoother on each track.
///
/// Tracks are reset between rallies — re-identification across rallies is
/// not a milestone-1 concern.
protocol PlayerTracking {
    /// Resets all tracks. Call at rally boundaries.
    func reset()

    /// Updates tracks with a new frame of pose observations and returns the
    /// tracked players for this frame.
    func update(with poses: [PoseObservation]) -> [TrackedPlayer]
}

final class PlayerTracker: PlayerTracking {
    func reset() {
        // TODO(milestone-1): clear track state.
    }

    func update(with poses: [PoseObservation]) -> [TrackedPlayer] {
        // TODO(milestone-1): IoU + Hungarian assignment, Kalman update.
        return []
    }
}
