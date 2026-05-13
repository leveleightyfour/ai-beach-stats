import Flutter
import Foundation

/// Bridges the Pigeon-generated `MLPipelineHostApi` to the native
/// `PipelineRunner`, and pushes events back to Dart via the
/// Pigeon-generated `MLPipelineEventListener` proxy.
///
/// One coordinator per app. Registered from `AppDelegate` once the Flutter
/// engine is available.
///
/// NOTE: This file references Pigeon-generated symbols
/// (`MLPipelineHostApi`, `MLPipelineHostApiSetup`, `MLPipelineEventListener`,
/// and the data types). They are emitted into
/// `ios/Runner/Pigeon/MLPipeline.g.swift` when you run
/// `dart run pigeon --input pigeons/ml_pipeline.dart`. If the generated
/// symbol names differ slightly in your Pigeon version, adjust the
/// references here.
final class MLPipelineCoordinator: MLPipelineHostApi {
    static let shared = MLPipelineCoordinator()

    private let sessionsQueue = DispatchQueue(
        label: "ai.beachstats.coordinator.sessions"
    )
    private var sessions: [String: Task<Void, Never>] = [:]
    private var eventListener: MLPipelineEventListener?
    private let runnerFactory: (PipelineRuntimeConfig) -> PipelineOrchestrating

    init(
        runnerFactory: @escaping (PipelineRuntimeConfig) -> PipelineOrchestrating =
            MLPipelineCoordinator.defaultRunnerFactory
    ) {
        self.runnerFactory = runnerFactory
    }

    static func defaultRunnerFactory(
        config: PipelineRuntimeConfig
    ) -> PipelineOrchestrating {
        PipelineRunner(
            frameExtractor: FrameExtractor(),
            ballDetector: BallDetector(
                confidenceThreshold: config.detectionConfidenceThreshold
            ),
            poseDetector: PoseDetector(),
            playerTracker: PlayerTracker(),
            rallySegmenter: RallySegmenter(),
            touchAttributor: TouchAttributor()
        )
    }

    /// Wires the coordinator into the Flutter engine. Call once during
    /// app launch with the FlutterViewController's binaryMessenger.
    static func register(with binaryMessenger: FlutterBinaryMessenger) {
        MLPipelineHostApiSetup.setUp(
            binaryMessenger: binaryMessenger,
            api: shared
        )
        shared.eventListener = MLPipelineEventListener(
            binaryMessenger: binaryMessenger
        )
    }

    // MARK: - MLPipelineHostApi

    func startProcessing(
        sessionId: String,
        matchId: String,
        videoPath: String,
        config: PipelineConfig,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let videoURL = URL(fileURLWithPath: videoPath)
        let runtimeConfig = PipelineRuntimeConfig(
            frameRateHz: Int(config.frameRateHz),
            rallyGapThreshold: config.rallyGapThresholdSeconds,
            minRallyDuration: config.minRallyDurationSeconds,
            touchProximityPx: config.touchProximityPx,
            detectionConfidenceThreshold: config.detectionConfidenceThreshold
        )

        let runner = runnerFactory(runtimeConfig)
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let stream = runner.run(
                sessionId: sessionId,
                matchId: matchId,
                videoURL: videoURL,
                config: runtimeConfig
            )
            for await event in stream {
                self.dispatch(event: event)
            }
            self.sessionsQueue.sync {
                _ = self.sessions.removeValue(forKey: sessionId)
            }
        }
        sessionsQueue.sync { sessions[sessionId] = task }
        completion(.success(()))
    }

    func cancel(sessionId: String) throws {
        sessionsQueue.sync {
            sessions[sessionId]?.cancel()
            sessions.removeValue(forKey: sessionId)
        }
    }

    // MARK: - Event dispatch

    private func dispatch(event: PipelineEvent) {
        // Pigeon Flutter API calls must originate on the platform thread.
        let listener = self.eventListener
        DispatchQueue.main.async {
            listener?.onPipelineEvent(event: event) { _ in
                // Acknowledge ignored; Dart-side handler is fire-and-forget.
            }
        }
    }
}
