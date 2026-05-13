import 'ball_observation.dart';
import 'touch_event.dart';

class Rally {
  const Rally({
    required this.rallyIndex,
    required this.startTimestampMs,
    required this.endTimestampMs,
    required this.touchCountBySlot,
    this.touches = const [],
    this.ballObservations = const [],
  });

  final int rallyIndex;
  final int startTimestampMs;
  final int endTimestampMs;

  /// Indexed by [PlayerSlot.index]. Always length 4.
  final List<int> touchCountBySlot;

  /// Empty when this Rally was built as a summary (e.g. for the timeline).
  /// Populated only when callers explicitly load detail.
  final List<TouchEvent> touches;
  final List<BallObservation> ballObservations;

  int get durationMs => endTimestampMs - startTimestampMs;

  int get totalTouches =>
      touchCountBySlot.fold<int>(0, (sum, count) => sum + count);
}
