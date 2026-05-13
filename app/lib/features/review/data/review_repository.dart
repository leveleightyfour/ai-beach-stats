import 'package:drift/drift.dart';

import '../../../shared/database/app_database.dart';
import '../../analysis/domain/ball_observation.dart';

class ReviewRepository {
  ReviewRepository(this._db);

  final AppDatabase _db;

  /// Streams the ball observations for [matchId] sorted by timestamp so the
  /// overlay can binary-search the active observation per frame.
  Stream<List<BallObservation>> watchObservations(String matchId) {
    final query = _db.select(_db.ballObservations)
      ..where((t) => t.matchId.equals(matchId))
      ..orderBy([(t) => OrderingTerm.asc(t.timestampMs)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  BallObservation _toDomain(BallObservationRow row) => BallObservation(
        frameIndex: row.frameIndex,
        timestampMs: row.timestampMs,
        x: row.x,
        y: row.y,
        width: row.width,
        height: row.height,
        confidence: row.confidence,
      );
}
