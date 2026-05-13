import 'ball_observation.dart';
import 'touch_event.dart';

class Rally {
  const Rally({
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

  /// Indexed by [PlayerSlot.index]. Always length 4.
  final List<int> touchCountBySlot;
  final List<TouchEvent> touches;
  final List<BallObservation> ballObservations;

  int get durationMs => endTimestampMs - startTimestampMs;
}
