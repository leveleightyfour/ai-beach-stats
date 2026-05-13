import 'package:drift/drift.dart';

import '../../../shared/database/app_database.dart';
import '../../analysis/domain/ball_observation.dart';
import '../../analysis/domain/rally.dart';

class ReviewRepository {
  ReviewRepository(this._db);

  final AppDatabase _db;

  /// Streams the ball observations for [matchId] sorted by timestamp so the
  /// overlay can binary-search the active observation per frame.
  Stream<List<BallObservation>> watchObservations(String matchId) {
    final query = _db.select(_db.ballObservations)
      ..where((t) => t.matchId.equals(matchId))
      ..orderBy([(t) => OrderingTerm.asc(t.timestampMs)]);
    return query.watch().map((rows) => rows.map(_toBallObservation).toList());
  }

  /// Streams the rally summaries for [matchId] in chronological order.
  /// Touches and per-rally observations are not loaded — the timeline only
  /// needs metadata + slot counts.
  Stream<List<Rally>> watchRallies(String matchId) {
    final query = _db.select(_db.rallies)
      ..where((t) => t.matchId.equals(matchId))
      ..orderBy([(t) => OrderingTerm.asc(t.rallyIndex)]);
    return query.watch().map((rows) => rows.map(_toRally).toList());
  }

  BallObservation _toBallObservation(BallObservationRow row) => BallObservation(
        frameIndex: row.frameIndex,
        timestampMs: row.timestampMs,
        x: row.x,
        y: row.y,
        width: row.width,
        height: row.height,
        confidence: row.confidence,
      );

  Rally _toRally(RallyRow row) => Rally(
        rallyIndex: row.rallyIndex,
        startTimestampMs: row.startMs,
        endTimestampMs: row.endMs,
        touchCountBySlot: [
          row.touchesHomeLeft,
          row.touchesHomeRight,
          row.touchesAwayLeft,
          row.touchesAwayRight,
        ],
      );
}
