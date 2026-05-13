import Foundation

/// Groups ball detections into rally spans by detecting gaps in continuous
/// ball presence.
///
/// Heuristic v1 (per the project brief):
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
        guard !detections.isEmpty else { return [] }

        let sorted = detections.sorted { $0.timestampMs < $1.timestampMs }
        let gapThresholdMs = Int((config.rallyGapThreshold * 1000).rounded())
        let minDurationMs = Int((config.minRallyDuration * 1000).rounded())

        var spans: [RallySpan] = []
        var rallyIndex = 0
        var spanStart = 0

        func closeSpan(endIndex: Int) {
            let first = sorted[spanStart]
            let last = sorted[endIndex]
            let durationMs = last.timestampMs - first.timestampMs
            guard durationMs >= minDurationMs else { return }
            spans.append(
                RallySpan(
                    rallyIndex: rallyIndex,
                    startFrameIndex: first.frameIndex,
                    endFrameIndex: last.frameIndex,
                    startTimestampMs: first.timestampMs,
                    endTimestampMs: last.timestampMs
                )
            )
            rallyIndex += 1
        }

        for i in 1..<sorted.count {
            let gap = sorted[i].timestampMs - sorted[i - 1].timestampMs
            if gap > gapThresholdMs {
                closeSpan(endIndex: i - 1)
                spanStart = i
            }
        }
        closeSpan(endIndex: sorted.count - 1)

        return spans
    }
}
