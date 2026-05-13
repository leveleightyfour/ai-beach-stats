import 'package:drift/drift.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/ml/ml_pipeline.g.dart';
import '../../library/data/match_repository.dart';

class AnalysisRepository {
  AnalysisRepository(this._db, this._matchRepository);

  final AppDatabase _db;
  final MatchRepository _matchRepository;

  /// Persists a completed pipeline run for [PipelineResult.matchId].
  /// Wipes any prior data for the match first so reprocessing is
  /// idempotent. All work runs in a single transaction; partial failures
  /// roll back.
  Future<void> persistResult(PipelineResult result) async {
    await _db.transaction(() async {
      await _wipeExisting(result.matchId);
      final rallyDriftIds = await _insertRallies(result);
      await _insertTouches(result, rallyDriftIds);
      await _insertObservations(result, rallyDriftIds);
      await _matchRepository.markProcessed(
        matchId: result.matchId,
        processedAt: DateTime.now(),
        frameWidth: result.frameWidth,
        frameHeight: result.frameHeight,
      );
    });
  }

  /// Wipes rallies, touches, observations, and clears the match's
  /// processedAt + frame dimensions. After this, the match looks
  /// freshly imported again and tapping it routes to /analysis.
  /// Single transaction; safe to call while the user is on /review.
  Future<void> resetResults(String matchId) async {
    await _db.transaction(() async {
      await _wipeExisting(matchId);
      await _matchRepository.clearProcessed(matchId);
    });
  }

  Future<void> _wipeExisting(String matchId) async {
    final rallyIdsForMatch = _db.selectOnly(_db.rallies)
      ..addColumns([_db.rallies.id])
      ..where(_db.rallies.matchId.equals(matchId));

    await (_db.delete(_db.touches)
          ..where((t) => t.rallyId.isInQuery(rallyIdsForMatch)))
        .go();
    await (_db.delete(_db.rallies)
          ..where((t) => t.matchId.equals(matchId)))
        .go();
    await (_db.delete(_db.ballObservations)
          ..where((t) => t.matchId.equals(matchId)))
        .go();
  }

  /// Returns a map from rallyIndex → drift autoincrement id so touches
  /// and observations can reference the right row.
  Future<Map<int, int>> _insertRallies(PipelineResult result) async {
    final ids = <int, int>{};
    for (final rally in result.rallies) {
      final counts = _slotCounts(rally.touchCountBySlot);
      final id = await _db.into(_db.rallies).insert(
            RalliesCompanion.insert(
              matchId: result.matchId,
              rallyIndex: rally.rallyIndex,
              startMs: rally.startTimestampMs,
              endMs: rally.endTimestampMs,
              touchesHomeLeft: Value(counts[0]),
              touchesHomeRight: Value(counts[1]),
              touchesAwayLeft: Value(counts[2]),
              touchesAwayRight: Value(counts[3]),
            ),
          );
      ids[rally.rallyIndex] = id;
    }
    return ids;
  }

  Future<void> _insertTouches(
    PipelineResult result,
    Map<int, int> rallyDriftIds,
  ) async {
    for (final rally in result.rallies) {
      final driftRallyId = rallyDriftIds[rally.rallyIndex];
      if (driftRallyId == null) continue;
      if (rally.touches.isEmpty) continue;
      await _db.batch((batch) {
        batch.insertAll(
          _db.touches,
          rally.touches.map(
            (t) => TouchesCompanion.insert(
              rallyId: driftRallyId,
              timestampMs: t.timestampMs,
              playerSlot: t.playerSlot.index,
              ballX: t.ballX,
              ballY: t.ballY,
            ),
          ),
        );
      });
    }
  }

  Future<void> _insertObservations(
    PipelineResult result,
    Map<int, int> rallyDriftIds,
  ) async {
    if (result.ballObservations.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAll(
        _db.ballObservations,
        result.ballObservations.map(
          (o) => BallObservationsCompanion.insert(
            matchId: result.matchId,
            rallyId: Value(_rallyIdFor(o.timestampMs, result.rallies, rallyDriftIds)),
            frameIndex: o.frameIndex,
            timestampMs: o.timestampMs,
            x: o.x,
            y: o.y,
            width: o.width,
            height: o.height,
            confidence: o.confidence,
          ),
        ),
      );
    });
  }

  int? _rallyIdFor(
    int timestampMs,
    List<RallyResult> rallies,
    Map<int, int> rallyDriftIds,
  ) {
    for (final rally in rallies) {
      if (timestampMs >= rally.startTimestampMs &&
          timestampMs <= rally.endTimestampMs) {
        return rallyDriftIds[rally.rallyIndex];
      }
    }
    return null;
  }

  /// Pads / truncates [raw] to a length-4 list of slot counts.
  List<int> _slotCounts(List<int> raw) {
    return [
      raw.isNotEmpty ? raw[0] : 0,
      raw.length > 1 ? raw[1] : 0,
      raw.length > 2 ? raw[2] : 0,
      raw.length > 3 ? raw[3] : 0,
    ];
  }
}
