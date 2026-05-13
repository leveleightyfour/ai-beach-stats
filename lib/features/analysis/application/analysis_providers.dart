import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/constants/pipeline_defaults.dart';
import '../../../shared/database/app_database_provider.dart';
import '../../../shared/ml/ml_pipeline.g.dart';
import '../../../shared/ml/ml_pipeline_providers.dart';
import '../../../shared/providers/documents_directory.dart';
import '../../library/application/library_providers.dart';
import '../data/analysis_repository.dart';
import 'analysis_state.dart';

part 'analysis_providers.g.dart';

@Riverpod(keepAlive: true)
AnalysisRepository analysisRepository(AnalysisRepositoryRef ref) {
  return AnalysisRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(matchRepositoryProvider),
  );
}

@riverpod
class AnalysisController extends _$AnalysisController {
  StreamSubscription<PipelineEvent>? _subscription;

  @override
  Future<AnalysisState> build(String matchId) async {
    debugPrint('[AnalysisController] build matchId=$matchId');
    final match = await ref.read(matchRepositoryProvider).findById(matchId);
    if (match == null) {
      debugPrint('[AnalysisController] match not found: $matchId');
      throw StateError('Match not found: $matchId');
    }

    if (match.isProcessed) {
      debugPrint('[AnalysisController] match already processed; short-circuit');
      return AnalysisState(match: match, alreadyProcessed: true);
    }

    final docsDir = ref.read(documentsDirectoryProvider);
    final absoluteVideoPath = p.join(docsDir, match.videoPath);
    debugPrint(
      '[AnalysisController] starting facade session videoPath=$absoluteVideoPath',
    );
    final facade = ref.read(mlPipelineFacadeProvider);
    final session = await facade.startSession(
      matchId: match.id,
      videoPath: absoluteVideoPath,
      config: _defaultConfig(),
    );
    debugPrint(
      '[AnalysisController] session started sessionId=${session.sessionId}',
    );

    _subscription = session.events.listen((event) {
      debugPrint(
        '[AnalysisController] event type=${event.type} '
        'frames=${event.progress?.framesProcessed} '
        'balls=${event.progress?.ballDetectionsSoFar} '
        'errorCode=${event.error?.code} '
        'errorMessage=${event.error?.message}',
      );
      final current = state.valueOrNull;
      if (current == null) return;
      final next = current.applying(event);
      state = AsyncData(next);
      if (event.type == PipelineEventType.completion && event.result != null) {
        debugPrint(
          '[AnalysisController] completion: rallies=${event.result!.rallies.length} '
          'observations=${event.result!.ballObservations.length}',
        );
        _persist(event.result!);
      }
    });

    ref.onDispose(() async {
      debugPrint('[AnalysisController] dispose');
      await _subscription?.cancel();
      _subscription = null;
      await session.cancel();
    });

    return AnalysisState(match: match);
  }

  Future<void> _persist(PipelineResult result) async {
    debugPrint(
      '[AnalysisController] persisting result for matchId=${result.matchId}',
    );
    try {
      await ref.read(analysisRepositoryProvider).persistResult(result);
      debugPrint('[AnalysisController] persist succeeded');
    } catch (error, stackTrace) {
      debugPrint('[AnalysisController] persist failed: $error\n$stackTrace');
    }
  }

  void retry() => ref.invalidateSelf();
}

PipelineConfig _defaultConfig() => PipelineConfig(
      frameRateHz: PipelineDefaults.frameRateHz,
      rallyGapThresholdSeconds: PipelineDefaults.rallyGapThresholdSeconds,
      minRallyDurationSeconds: PipelineDefaults.minRallyDurationSeconds,
      touchProximityPx: PipelineDefaults.touchProximityPx,
      detectionConfidenceThreshold:
          PipelineDefaults.detectionConfidenceThreshold,
    );
