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
    this.alreadyProcessed = false,
  });

  final Match match;
  final PipelineProgress? latestProgress;
  final PipelineResult? result;
  final String? errorMessage;
  final bool wasCancelled;

  /// True if the controller short-circuited because the match had already
  /// been processed when the screen opened. The UI shows a CTA to open
  /// the review screen rather than running the pipeline again.
  final bool alreadyProcessed;

  bool get isComplete =>
      result != null ||
      errorMessage != null ||
      wasCancelled ||
      alreadyProcessed;

  AnalysisState applying(PipelineEvent event) {
    switch (event.type) {
      case PipelineEventType.progress:
        return AnalysisState(
          match: match,
          latestProgress: event.progress ?? latestProgress,
          result: result,
          errorMessage: errorMessage,
          wasCancelled: wasCancelled,
          alreadyProcessed: alreadyProcessed,
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
