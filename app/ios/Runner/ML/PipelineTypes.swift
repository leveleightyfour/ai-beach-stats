import CoreMedia
import Foundation

/// Tunable pipeline parameters, mirrored from the Dart `PipelineConfig`.
/// The Pigeon-generated `PipelineConfig` is the source of truth on the wire;
/// this struct exists as a Swift-idiomatic working copy for the pipeline.
struct PipelineRuntimeConfig {
    let frameRateHz: Int
    let rallyGapThreshold: TimeInterval
    let minRallyDuration: TimeInterval
    let touchProximityPx: Double
    let detectionConfidenceThreshold: Double
}

/// One sampled frame travelling through the pipeline.
struct PipelineFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let frameIndex: Int
}

/// Single bounding-box ball detection at a moment in time.
struct BallDetection {
    let frameIndex: Int
    let timestampMs: Int
    let boundingBox: CGRect
    let confidence: Double
}

/// Pose observation for a single person within a frame.
struct PoseObservation {
    let frameIndex: Int
    let timestampMs: Int
    let keypoints: [CGPoint]
    let boundingBox: CGRect
}

/// Stable per-rally player identity assigned by `PlayerTracker`.
typealias PlayerTrackId = Int

struct TrackedPlayer {
    let trackId: PlayerTrackId
    let frameIndex: Int
    let centroid: CGPoint
    let boundingBox: CGRect
}

/// A continuous span identified by the rally segmenter.
struct RallySpan {
    let rallyIndex: Int
    let startFrameIndex: Int
    let endFrameIndex: Int
    let startTimestampMs: Int
    let endTimestampMs: Int
}

/// Single attributed touch. `playerSlotIndex` matches the on-the-wire
/// `PlayerSlot` ordinal (0=homeLeft, 1=homeRight, 2=awayLeft, 3=awayRight).
struct AttributedTouch {
    let timestampMs: Int
    let playerSlotIndex: Int
    let ballPosition: CGPoint
}
