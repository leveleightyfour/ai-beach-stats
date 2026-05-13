import Foundation

/// Top-level orchestrator. Owns one session at a time and emits
/// `PipelineEvent`s via the Pigeon-generated `MLPipelineEvents` channel.
///
/// All pipeline stages are injected for testability. Concurrency model:
/// each session runs on a dedicated `Task` and can be cancelled by
/// `MLPipelineHostApi.cancel(sessionId:)`.
protocol PipelineOrchestrating {
    func start(
        matchId: String,
        videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> String

    func cancel(sessionId: String)
}

final class PipelineRunner: PipelineOrchestrating {
    init(
        frameExtractor: FrameExtracting,
        ballDetector: BallDetecting,
        poseDetector: PoseDetecting,
        playerTracker: PlayerTracking,
        rallySegmenter: RallySegmenting,
        touchAttributor: TouchAttributing
    ) {
        self.frameExtractor = frameExtractor
        self.ballDetector = ballDetector
        self.poseDetector = poseDetector
        self.playerTracker = playerTracker
        self.rallySegmenter = rallySegmenter
        self.touchAttributor = touchAttributor
    }

    private let frameExtractor: FrameExtracting
    private let ballDetector: BallDetecting
    private let poseDetector: PoseDetecting
    private let playerTracker: PlayerTracking
    private let rallySegmenter: RallySegmenting
    private let touchAttributor: TouchAttributing

    func start(
        matchId: String,
        videoURL: URL,
        config: PipelineRuntimeConfig
    ) -> String {
        // TODO(milestone-1): spawn a Task that drives the stages in order
        // and emits PipelineEvents via the event channel sink.
        return UUID().uuidString
    }

    func cancel(sessionId: String) {
        // TODO(milestone-1): look up the Task by sessionId and cancel.
    }
}
