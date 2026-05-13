class Match {
  const Match({
    required this.id,
    required this.title,
    required this.videoPath,
    required this.durationMs,
    required this.importedAt,
    this.thumbnailPath,
  });

  final String id;
  final String title;
  final String videoPath;
  final int durationMs;
  final DateTime importedAt;
  final String? thumbnailPath;
}
