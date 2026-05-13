import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/constants/pipeline_defaults.dart';
import '../../../shared/database/app_database_provider.dart';
import '../../../shared/ml/ml_pipeline.g.dart';
import '../../../shared/ml/ml_pipeline_providers.dart';
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
    final match = await ref.read(matchRepositoryProvider).findById(matchId);
    if (match == null) {
      throw StateError('Match not found: $matchId');
    }

    if (match.isProcessed) {
      // Pipeline already ran for this match — don't re-run.
      return AnalysisState(match: match, alreadyProcessed: true);
    }

    final facade = ref.read(mlPipelineFacadeProvider);
    final session = await facade.startSession(
      matchId: match.id,
      videoPath: match.videoPath,
      config: _defaultConfig(),
    );

    _subscription = session.events.listen((event) {
      final current = state.valueOrNull;
      if (current == null) return;
      final next = current.applying(event);
      state = AsyncData(next);
      if (event.type == PipelineEventType.completion && event.result != null) {
        _persist(event.result!);
      }
    });

    ref.onDispose(() async {
      await _subscription?.cancel();
      _subscription = null;
      await session.cancel();
    });

    return AnalysisState(match: match);
  }

  Future<void> _persist(PipelineResult result) async {
    try {
      await ref.read(analysisRepositoryProvider).persistResult(result);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to persist pipeline result: $error\n$stackTrace');
      }
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
