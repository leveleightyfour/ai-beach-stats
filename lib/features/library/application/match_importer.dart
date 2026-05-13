import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../domain/match.dart';
import 'library_providers.dart';

part 'match_importer.g.dart';

class MatchImportFailed implements Exception {
  MatchImportFailed(this.message);
  final String message;
  @override
  String toString() => 'MatchImportFailed: $message';
}

@riverpod
class MatchImporter extends _$MatchImporter {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Picks a video from the Photos library, persists it as a [Match], and
  /// returns the inserted match. Returns `null` if the user cancelled.
  Future<Match?> importFromGallery() async {
    state = const AsyncLoading();
    try {
      final match = await _runImport();
      state = const AsyncData(null);
      return match;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }

  Future<Match?> _runImport() async {
    debugPrint('[MatchImporter] launching picker');
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) {
      debugPrint('[MatchImporter] picker cancelled');
      return null;
    }
    debugPrint('[MatchImporter] picked path=${picked.path}');
    return _persistVideoFile(File(picked.path));
  }

  Future<Match> _persistVideoFile(File source) async {
    final id = const Uuid().v4();
    final docDir = await getApplicationDocumentsDirectory();
    final videosDir = Directory(p.join(docDir.path, 'videos'));
    final thumbsDir = Directory(p.join(docDir.path, 'thumbnails'));
    await videosDir.create(recursive: true);
    await thumbsDir.create(recursive: true);

    final videoPath = p.join(videosDir.path, '$id.mp4');
    debugPrint('[MatchImporter] copying source -> $videoPath');
    await source.copy(videoPath);

    final durationMs = await _readDurationMs(File(videoPath));
    debugPrint('[MatchImporter] durationMs=$durationMs');
    final thumbnailPath = await _generateThumbnail(videoPath, thumbsDir.path);
    debugPrint('[MatchImporter] thumbnailPath=$thumbnailPath');

    final now = DateTime.now();
    final match = Match(
      id: id,
      title: _deriveTitle(now),
      videoPath: videoPath,
      durationMs: durationMs,
      importedAt: now,
      thumbnailPath: thumbnailPath,
    );

    await ref.read(matchRepositoryProvider).insert(match);
    debugPrint('[MatchImporter] inserted match id=$id');
    return match;
  }

  Future<int> _readDurationMs(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      if (duration == Duration.zero) {
        throw MatchImportFailed('Could not read video duration.');
      }
      return duration.inMilliseconds;
    } finally {
      await controller.dispose();
    }
  }

  Future<String?> _generateThumbnail(String videoPath, String outputDir) async {
    try {
      return await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: outputDir,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 640,
        quality: 75,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Thumbnail generation failed: $error\n$stackTrace');
      }
      return null;
    }
  }

  String _deriveTitle(DateTime when) =>
      'Match — ${DateFormat('d MMM y, HH:mm').format(when)}';
}
