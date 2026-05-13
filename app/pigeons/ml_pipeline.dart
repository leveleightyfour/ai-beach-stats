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
///
/// All values are exposed to Dart so they can be surfaced in a debug panel
/// without recompiling native code. Defaults are documented in
/// [PipelineDefaults] on the Dart side.
class PipelineConfig {
  PipelineConfig({
    required this.frameRateHz,
    required this.rallyGapThresholdSeconds,
    required this.minRallyDurationSeconds,
    required this.touchProximityPx,
    required this.detectionConfidenceThreshold,
  });

  /// Frames per second extracted from the source video.
  /// Default 15. Lower values miss fast trajectory changes; higher values
  /// raise CPU/Neural Engine load.
  final int frameRateHz;

  /// Maximum gap (in seconds) with no ball detection before the current
  /// rally is considered ended.
  final double rallyGapThresholdSeconds;

  /// Spans shorter than this are dropped as noise.
  final double minRallyDurationSeconds;

  /// Pixel distance (at source resolution) within which a player is
  /// considered to be in contact with the ball.
  final double touchProximityPx;

  /// Detection confidence below this is ignored.
  final double detectionConfidenceThreshold;
}

/// Coarse-grained stage the pipeline is currently in.
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

/// Player slot relative to the camera. Slots reset between rallies.
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
  });

  final PipelineStage stage;

  /// 0.0 .. 1.0 across the whole pipeline (not per-stage).
  final double fractionComplete;
  final int framesProcessed;
  final int totalFrames;
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

  /// Bounding box in source-video pixel coordinates.
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
    required this.totalFramesProcessed,
    required this.totalDurationMs,
  });

  final String matchId;
  final List<RallyResult> rallies;
  final int totalFramesProcessed;
  final int totalDurationMs;
}

class PipelineError {
  PipelineError({required this.code, required this.message});
  final String code;
  final String message;
}

/// Discriminator for [PipelineEvent].
enum PipelineEventType {
  progress,
  completion,
  cancelled,
  error,
}

/// Single event type carried over the event channel. Exactly one of
/// [progress], [result], or [error] is populated, based on [type].
///
/// Sealed classes are intentionally avoided here for v1 — Pigeon's
/// cross-platform sealed-class support is still maturing and we want a
/// boring, portable surface area while we iterate.
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
  /// Starts processing the video at [videoPath] for the given [matchId].
  /// Returns a sessionId that the caller subscribes to via [MLPipelineEvents].
  @async
  String startProcessing(
    String matchId,
    String videoPath,
    PipelineConfig config,
  );

  /// Cancels an in-flight session. Idempotent.
  void cancel(String sessionId);
}

/// Swift -> Dart stream of pipeline events for a given session.
/// Subscribers should filter by [PipelineEvent.sessionId].
@EventChannelApi()
abstract class MLPipelineEvents {
  PipelineEvent pipelineEvents();
}
