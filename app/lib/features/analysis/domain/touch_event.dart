import 'player_slot.dart';

class TouchEvent {
  const TouchEvent({
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
