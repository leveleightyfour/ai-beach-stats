import 'package:drift/drift.dart';

import '../../../shared/database/app_database.dart';
import '../domain/match.dart';

class MatchRepository {
  MatchRepository(this._db);

  final AppDatabase _db;

  Stream<List<Match>> watchAll() {
    final query = _db.select(_db.matches)
      ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  Stream<Match?> watchById(String id) {
    final query = _db.select(_db.matches)..where((t) => t.id.equals(id));
    return query
        .watchSingleOrNull()
        .map((row) => row == null ? null : _toDomain(row));
  }

  Future<Match?> findById(String id) async {
    final row = await (_db.select(_db.matches)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<void> insert(Match match) async {
    await _db.into(_db.matches).insert(
          MatchesCompanion.insert(
            id: match.id,
            title: match.title,
            videoPath: match.videoPath,
            durationMs: match.durationMs,
            importedAt: match.importedAt,
            thumbnailPath: Value(match.thumbnailPath),
            processedAt: Value(match.processedAt),
            frameWidth: Value(match.frameWidth),
            frameHeight: Value(match.frameHeight),
            pipelineDurationMs: Value(match.pipelineDurationMs),
          ),
        );
  }

  Future<void> markProcessed({
    required String matchId,
    required DateTime processedAt,
    required int frameWidth,
    required int frameHeight,
    required int pipelineDurationMs,
  }) async {
    await (_db.update(_db.matches)..where((t) => t.id.equals(matchId))).write(
      MatchesCompanion(
        processedAt: Value(processedAt),
        frameWidth: Value(frameWidth),
        frameHeight: Value(frameHeight),
        pipelineDurationMs: Value(pipelineDurationMs),
      ),
    );
  }

  Future<void> clearProcessed(String matchId) async {
    await (_db.update(_db.matches)..where((t) => t.id.equals(matchId))).write(
      const MatchesCompanion(
        processedAt: Value(null),
        frameWidth: Value(null),
        frameHeight: Value(null),
        pipelineDurationMs: Value(null),
      ),
    );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.matches)..where((t) => t.id.equals(id))).go();
  }

  Match _toDomain(MatchRow row) => Match(
        id: row.id,
        title: row.title,
        videoPath: row.videoPath,
        durationMs: row.durationMs,
        importedAt: row.importedAt,
        thumbnailPath: row.thumbnailPath,
        processedAt: row.processedAt,
        frameWidth: row.frameWidth,
        frameHeight: row.frameHeight,
        pipelineDurationMs: row.pipelineDurationMs,
      );
}
