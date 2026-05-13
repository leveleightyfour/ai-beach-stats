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

  /// Path relative to the app's documents directory. Resolve to an
  /// absolute path via `p.join(documentsDirectoryProvider, videoPath)`
  /// before opening the file. Stored relative so iOS container-UUID
  /// rotations across rebuilds don't break existing rows.
  final String videoPath;
  final int durationMs;
  final DateTime importedAt;

  /// Path relative to the app's documents directory; see [videoPath].
  final String? thumbnailPath;

  /// Non-null once the pipeline has produced a successful result for this
  /// match. Drives library badges and routing.
  final DateTime? processedAt;

  /// Source-video resolution recorded during processing.
  final int? frameWidth;
  final int? frameHeight;

  bool get isProcessed => processedAt != null;
}
