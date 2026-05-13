class Match {
  const Match({
    required this.id,
    required this.title,
    required this.videoPath,
    required this.durationMs,
    required this.importedAt,
    this.thumbnailPath,
    this.processedAt,
    this.frameWidth,
    this.frameHeight,
  });

  final String id;
  final String title;
  final String videoPath;
  final int durationMs;
  final DateTime importedAt;
  final String? thumbnailPath;

  /// Non-null once the pipeline has produced a successful result for this
  /// match. Drives library badges and routing.
  final DateTime? processedAt;

  /// Source-video resolution recorded during processing.
  final int? frameWidth;
  final int? frameHeight;

  bool get isProcessed => processedAt != null;
}
