import 'package:drift/drift.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/ml/ml_pipeline.g.dart';
import '../../library/data/match_repository.dart';

class AnalysisRepository {
  AnalysisRepository(this._db, this._matchRepository);

  final AppDatabase _db;
  final MatchRepository _matchRepository;

  /// Persists a completed pipeline run for [matchId]. Replaces any existing
  /// ball observations for the match so reprocessing is idempotent.
  Future<void> persistResult(PipelineResult result) async {
    await _db.transaction(() async {
      await (_db.delete(_db.ballObservations)
            ..where((t) => t.matchId.equals(result.matchId)))
          .go();

      if (result.ballObservations.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.ballObservations,
            result.ballObservations.map(
              (o) => BallObservationsCompanion.insert(
                matchId: result.matchId,
                rallyId: const Value(null),
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

      await _matchRepository.markProcessed(
        matchId: result.matchId,
        processedAt: DateTime.now(),
        frameWidth: result.frameWidth,
        frameHeight: result.frameHeight,
      );
    });
  }
}
