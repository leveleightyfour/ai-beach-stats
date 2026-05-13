import 'package:flutter/foundation.dart';

import '../../../shared/ml/ml_pipeline.g.dart';
import '../../library/domain/match.dart';

/// Snapshot of an in-flight (or completed) analysis session, fed to the UI.
@immutable
class AnalysisState {
  const AnalysisState({
    required this.match,
    this.latestProgress,
    this.result,
    this.errorMessage,
    this.wasCancelled = false,
  });

  final Match match;
  final PipelineProgress? latestProgress;
  final PipelineResult? result;
  final String? errorMessage;
  final bool wasCancelled;

  bool get isComplete =>
      result != null || errorMessage != null || wasCancelled;

  AnalysisState applying(PipelineEvent event) {
    switch (event.type) {
      case PipelineEventType.progress:
        return AnalysisState(
          match: match,
          latestProgress: event.progress ?? latestProgress,
          result: result,
          errorMessage: errorMessage,
          wasCancelled: wasCancelled,
        );
      case PipelineEventType.completion:
        return AnalysisState(
          match: match,
          latestProgress: latestProgress,
          result: event.result,
        );
      case PipelineEventType.cancelled:
        return AnalysisState(
          match: match,
          latestProgress: latestProgress,
          wasCancelled: true,
        );
      case PipelineEventType.error:
        return AnalysisState(
          match: match,
          latestProgress: latestProgress,
          errorMessage: event.error?.message ?? 'Unknown error',
        );
    }
  }
}
