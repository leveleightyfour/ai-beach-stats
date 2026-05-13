// Pigeon interface for the on-device ML pipeline.
//
// Regenerate after editing this file:
//   dart run pigeon --input pigeons/ml_pipeline.dart
//
// This file is the single source of truth for the Dart <-> Swift boundary.
// Do not edit the generated `lib/shared/ml/ml_pipeline.g.dart` or
// `ios/Runner/Pigeon/MLPipeline.g.swift` outputs by hand.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/shared/ml/ml_pipeline.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'ios/Runner/Pigeon/MLPipeline.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'ai_beach_stats',
  ),
)

/// Tunable parameters for one end-to-end pipeline run.
class PipelineConfig {
  PipelineConfig({
    required this.frameRateHz,
    required this.rallyGapThresholdSeconds,
    required this.minRallyDurationSeconds,
    required this.touchProximityPx,
    required this.detectionConfidenceThreshold,
  });

  final int frameRateHz;
  final double rallyGapThresholdSeconds;
  final double minRallyDurationSeconds;
  final double touchProximityPx;
  final double detectionConfidenceThreshold;
}

enum PipelineStage {
  initialising,
  extractingFrames,
  detectingBall,
  detectingPoses,
  trackingPlayers,
  segmentingRallies,
  attributingTouches,
  finalising,
}

enum PlayerSlot {
  homeLeft,
  homeRight,
  awayLeft,
  awayRight,
}

class PipelineProgress {
  PipelineProgress({
    required this.stage,
    required this.fractionComplete,
    required this.framesProcessed,
    required this.totalFrames,
    required this.ballDetectionsSoFar,
    this.previewThumbnailPath,
  });

  final PipelineStage stage;

  /// 0.0 .. 1.0 across the whole pipeline (not per-stage).
  final double fractionComplete;
  final int framesProcessed;
  final int totalFrames;

  /// Running count of frames in which the ball was detected with
  /// confidence above the configured threshold. Zero when the
  /// detection model is unavailable.
  final int ballDetectionsSoFar;

  /// Absolute path to a debug preview thumbnail (typically the first frame).
  /// Populated once, early in the run.
  final String? previewThumbnailPath;
}

class BallObservation {
  BallObservation({
    required this.frameIndex,
    required this.timestampMs,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  final int frameIndex;
  final int timestampMs;
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
}

class TouchEvent {
  TouchEvent({
    required this.timestampMs,
    required this.playerSlot,
    required this.ballX,
    required this.ballY,
  });

  final int timestampMs;
  final PlayerSlot playerSlot;
  final double ballX;
  final double ballY;
}

class RallyResult {
  RallyResult({
    required this.rallyIndex,
    required this.startTimestampMs,
    required this.endTimestampMs,
    required this.touchCountBySlot,
    required this.touches,
    required this.ballObservations,
  });

  final int rallyIndex;
  final int startTimestampMs;
  final int endTimestampMs;

  /// Indexed by PlayerSlot.index. Length is always 4.
  final List<int> touchCountBySlot;
  final List<TouchEvent> touches;
  final List<BallObservation> ballObservations;
}

class PipelineResult {
  PipelineResult({
    required this.matchId,
    required this.rallies,
    required this.ballObservations,
    required this.frameWidth,
    required this.frameHeight,
    required this.totalFramesProcessed,
    required this.totalBallDetections,
    required this.totalDurationMs,
  });

  final String matchId;
  final List<RallyResult> rallies;

  /// All ball detections from the run, in chronological order. Once rally
  /// segmentation lands these will move into [RallyResult.ballObservations]
  /// and this list will likely disappear; for now they're shipped flat so
  /// the review screen can render an overlay without rallies existing yet.
  final List<BallObservation> ballObservations;

  /// Source-video resolution. The review-screen overlay needs this to map
  /// ball bounding boxes (which are in source-pixel coords) into Flutter
  /// layout coordinates.
  final int frameWidth;
  final int frameHeight;

  final int totalFramesProcessed;

  /// Total frames in which the ball was detected with confidence above
  /// the configured threshold. Independent of rally segmentation.
  final int totalBallDetections;
  final int totalDurationMs;
}

class PipelineError {
  PipelineError({required this.code, required this.message});
  final String code;
  final String message;
}

enum PipelineEventType {
  progress,
  completion,
  cancelled,
  error,
}

/// Single event type carried over the @FlutterApi channel.
/// Exactly one of [progress], [result], or [error] is populated.
class PipelineEvent {
  PipelineEvent({
    required this.sessionId,
    required this.type,
    this.progress,
    this.result,
    this.error,
  });

  final String sessionId;
  final PipelineEventType type;
  final PipelineProgress? progress;
  final PipelineResult? result;
  final PipelineError? error;
}

/// Dart -> Swift control surface.
@HostApi()
abstract class MLPipelineHostApi {
  /// Starts processing the video at [videoPath]. [sessionId] is generated by
  /// Dart so the Dart side can subscribe to events for the session before
  /// the call returns, avoiding a startup race.
  @async
  void startProcessing(
    String sessionId,
    String matchId,
    String videoPath,
    PipelineConfig config,
  );

  /// Cancels an in-flight session. Idempotent.
  void cancel(String sessionId);
}

/// Swift -> Dart events. Implemented by the Dart facade and invoked by the
/// native pipeline coordinator as each event occurs.
@FlutterApi()
abstract class MLPipelineEventListener {
  void onPipelineEvent(PipelineEvent event);
}
