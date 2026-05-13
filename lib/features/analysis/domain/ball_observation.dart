class BallObservation {
  const BallObservation({
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
