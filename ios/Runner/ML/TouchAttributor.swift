import CoreGraphics
import Foundation

/// Detects per-rally touch events and attributes each to a player slot.
///
/// Touch detection (milestone 6, naive):
/// - For each interior triple of ball detections within a rally
///   `(t-1, t, t+1)`, compute the angle between the in-velocity and
///   out-velocity vectors at frame `t`.
/// - If the angle exceeds `directionChangeThreshold` AND a player pose
///   is within `config.touchProximityPx` of the ball at frame `t`, emit
///   a touch attributed to the nearest pose's quadrant.
///
/// Slot derivation uses the source-pixel quadrant of the pose centroid:
/// left/right by `x < frameSize.width / 2`, home/away by `y >= frameSize
/// .height / 2`. Assumes a tripod framing with the home team occupying
/// the bottom half of the frame. Court homography (a proper coordinate
/// mapping) is a later-milestone concern.
protocol TouchAttributing {
    func attribute(
        rally: RallySpan,
        ballDetections: [BallDetection],
        posesByFrame: [Int: [PoseObservation]],
        config: PipelineRuntimeConfig,
        frameSize: CGSize
    ) -> [AttributedTouch]
}

final class TouchAttributor: TouchAttributing {
    init(directionChangeThreshold: Double = .pi / 3) {
        self.directionChangeThreshold = directionChangeThreshold
    }

    /// Minimum angle (radians) between in-velocity and out-velocity that
    /// counts as a "sharp" direction change. Default 60°.
    private let directionChangeThreshold: Double

    func attribute(
        rally: RallySpan,
        ballDetections: [BallDetection],
        posesByFrame: [Int: [PoseObservation]],
        config: PipelineRuntimeConfig,
        frameSize: CGSize
    ) -> [AttributedTouch] {
        let inRally = ballDetections
            .filter { detection in
                detection.timestampMs >= rally.startTimestampMs
                    && detection.timestampMs <= rally.endTimestampMs
            }
            .sorted { $0.timestampMs < $1.timestampMs }

        guard inRally.count >= 3 else { return [] }

        var touches: [AttributedTouch] = []

        for i in 1..<(inRally.count - 1) {
            let prev = inRally[i - 1]
            let curr = inRally[i]
            let next = inRally[i + 1]

            let prevCentre = Self.centre(of: prev.boundingBox)
            let currCentre = Self.centre(of: curr.boundingBox)
            let nextCentre = Self.centre(of: next.boundingBox)

            let vIn = CGPoint(
                x: currCentre.x - prevCentre.x,
                y: currCentre.y - prevCentre.y
            )
            let vOut = CGPoint(
                x: nextCentre.x - currCentre.x,
                y: nextCentre.y - currCentre.y
            )

            let angleChange = Self.angleBetween(vIn, vOut)
            guard angleChange >= directionChangeThreshold else { continue }

            let poses = posesByFrame[curr.frameIndex] ?? []
            guard let nearestPose = Self.nearestPose(
                poses: poses,
                ballPosition: currCentre,
                maxDistance: config.touchProximityPx
            ) else { continue }

            let slotIndex = Self.slot(
                for: Self.centre(of: nearestPose.boundingBox),
                frameSize: frameSize
            )
            touches.append(
                AttributedTouch(
                    timestampMs: curr.timestampMs,
                    playerSlotIndex: slotIndex,
                    ballPosition: currCentre
                )
            )
        }

        return touches
    }

    private static func centre(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func angleBetween(_ a: CGPoint, _ b: CGPoint) -> Double {
        let magA = sqrt(Double(a.x * a.x + a.y * a.y))
        let magB = sqrt(Double(b.x * b.x + b.y * b.y))
        guard magA > 0, magB > 0 else { return 0 }
        let dot = Double(a.x * b.x + a.y * b.y) / (magA * magB)
        return acos(max(-1, min(1, dot)))
    }

    private static func nearestPose(
        poses: [PoseObservation],
        ballPosition: CGPoint,
        maxDistance: Double
    ) -> PoseObservation? {
        var best: PoseObservation?
        var bestDistance = Double.infinity
        for pose in poses {
            let centre = self.centre(of: pose.boundingBox)
            let dx = Double(centre.x - ballPosition.x)
            let dy = Double(centre.y - ballPosition.y)
            let distance = sqrt(dx * dx + dy * dy)
            if distance < bestDistance && distance <= maxDistance {
                bestDistance = distance
                best = pose
            }
        }
        return best
    }

    /// Maps a pose centroid in source-pixel coords to a `PlayerSlot`
    /// ordinal (0=homeLeft, 1=homeRight, 2=awayLeft, 3=awayRight).
    /// Home = bottom half, away = top half.
    private static func slot(for point: CGPoint, frameSize: CGSize) -> Int {
        let isRight = point.x >= frameSize.width / 2
        let isHome = point.y >= frameSize.height / 2
        if isHome {
            return isRight ? 1 : 0
        } else {
            return isRight ? 3 : 2
        }
    }
}
