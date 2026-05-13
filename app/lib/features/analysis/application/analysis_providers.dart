import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/constants/pipeline_defaults.dart';
import '../../../shared/ml/ml_pipeline.g.dart';
import '../../../shared/ml/ml_pipeline_providers.dart';
import '../../library/application/library_providers.dart';
import 'analysis_state.dart';

part 'analysis_providers.g.dart';

@riverpod
class AnalysisController extends _$AnalysisController {
  StreamSubscription<PipelineEvent>? _subscription;

  @override
  Future<AnalysisState> build(String matchId) async {
    final match = await ref.read(matchRepositoryProvider).findById(matchId);
    if (match == null) {
      throw StateError('Match not found: $matchId');
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
      state = AsyncData(current.applying(event));
    });

    ref.onDispose(() async {
      await _subscription?.cancel();
      _subscription = null;
      await session.cancel();
    });

    return AnalysisState(match: match);
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
