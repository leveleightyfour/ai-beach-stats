import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/duration_format.dart';
import '../../../shared/ml/ml_pipeline.g.dart';
import '../application/analysis_providers.dart';
import '../application/analysis_state.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(analysisControllerProvider(matchId));
    return Scaffold(
      appBar: AppBar(
        title: Text(analysis.valueOrNull?.match.title ?? 'Processing'),
      ),
      body: analysis.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ScreenError(
          message: 'Could not start analysis.\n$error',
          onRetry: () =>
              ref.read(analysisControllerProvider(matchId).notifier).retry(),
        ),
        data: (state) => _AnalysisBody(
          state: state,
          onRetry: () =>
              ref.read(analysisControllerProvider(matchId).notifier).retry(),
        ),
      ),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  const _AnalysisBody({required this.state, required this.onRetry});

  final AnalysisState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          _PreviewThumbnail(path: state.latestProgress?.previewThumbnailPath),
          const SizedBox(height: AppSpacing.l),
          if (state.alreadyProcessed)
            _AlreadyProcessedBlock(matchId: state.match.id)
          else if (state.errorMessage != null)
            _ErrorBlock(message: state.errorMessage!, onRetry: onRetry)
          else if (state.wasCancelled)
            const _StatusBlock(
              title: 'Cancelled',
              detail: 'Processing was cancelled before completion.',
            )
          else if (state.result != null)
            _ResultBlock(matchId: state.match.id, result: state.result!)
          else
            _ProgressBlock(progress: state.latestProgress),
        ],
      ),
    );
  }
}

class _PreviewThumbnail extends StatelessWidget {
  const _PreviewThumbnail({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.m),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: path == null
            ? Container(
                color: colors.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.movie_creation_outlined,
                  color: colors.onSurfaceVariant,
                  size: 48,
                ),
              )
            : Image.file(
                File(path!),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => Container(
                  color: colors.surfaceContainerHighest,
                ),
              ),
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.progress});

  final PipelineProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final mutedStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _stageLabel(p?.stage),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          p == null
              ? 'Starting…'
              : '${p.framesProcessed} / ${p.totalFrames} frames',
          style: mutedStyle,
        ),
        if (p != null) ...[
          const SizedBox(height: 2),
          Text(
            '${p.ballDetectionsSoFar} ball detections',
            style: mutedStyle,
          ),
        ],
        const SizedBox(height: AppSpacing.s),
        LinearProgressIndicator(
          value: p == null || p.totalFrames == 0
              ? null
              : (p.fractionComplete).clamp(0.0, 1.0),
          minHeight: 6,
        ),
      ],
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.matchId, required this.result});

  final String matchId;
  final PipelineResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Done',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Stat(label: 'Frames processed', value: '${result.totalFramesProcessed}'),
        _Stat(
          label: 'Ball detections',
          value: '${result.totalBallDetections}',
        ),
        _Stat(
          label: 'Pipeline duration',
          value: formatDurationMs(result.totalDurationMs),
        ),
        _Stat(label: 'Rallies detected', value: '${result.rallies.length}'),
        const SizedBox(height: AppSpacing.l),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => context.pushReplacement('/review/$matchId'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Open review'),
          ),
        ),
      ],
    );
  }
}

class _AlreadyProcessedBlock extends StatelessWidget {
  const _AlreadyProcessedBlock({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Already processed',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Pipeline results are ready. Open review to inspect detections.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => context.pushReplacement('/review/$matchId'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Open review'),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          detail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Processing failed',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.m),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

class _ScreenError extends StatelessWidget {
  const _ScreenError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.m),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _stageLabel(PipelineStage? stage) {
  switch (stage) {
    case null:
    case PipelineStage.initialising:
      return 'Initialising…';
    case PipelineStage.extractingFrames:
      return 'Extracting frames';
    case PipelineStage.detectingBall:
      return 'Detecting ball';
    case PipelineStage.detectingPoses:
      return 'Detecting players';
    case PipelineStage.trackingPlayers:
      return 'Tracking players';
    case PipelineStage.segmentingRallies:
      return 'Segmenting rallies';
    case PipelineStage.attributingTouches:
      return 'Attributing touches';
    case PipelineStage.finalising:
      return 'Finalising';
  }
}
