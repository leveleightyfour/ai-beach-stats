import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/duration_format.dart';
import '../../../analysis/domain/rally.dart';
import '../../../library/domain/match.dart';

/// Persistent card under the rally-timeline header showing aggregate
/// touches across the whole match by slot. Hidden when total touches = 0
/// so it doesn't add visual weight to empty matches.
class MatchTouchSummary extends StatelessWidget {
  const MatchTouchSummary({required this.rallies, super.key});

  final List<Rally> rallies;

  @override
  Widget build(BuildContext context) {
    final totals = _aggregate(rallies);
    final total = totals.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s,
        0,
        AppSpacing.s,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text('Touches', style: labelStyle),
          const SizedBox(width: AppSpacing.s),
          _SlotPair(label: 'HL', value: totals[0], valueStyle: valueStyle),
          const SizedBox(width: AppSpacing.s),
          _SlotPair(label: 'HR', value: totals[1], valueStyle: valueStyle),
          const SizedBox(width: AppSpacing.s),
          _SlotPair(label: 'AL', value: totals[2], valueStyle: valueStyle),
          const SizedBox(width: AppSpacing.s),
          _SlotPair(label: 'AR', value: totals[3], valueStyle: valueStyle),
        ],
      ),
    );
  }
}

class _SlotPair extends StatelessWidget {
  const _SlotPair({
    required this.label,
    required this.value,
    required this.valueStyle,
  });

  final String label;
  final int value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text('$value', style: valueStyle),
      ],
    );
  }
}

/// Bottom sheet behind the AppBar info icon. Surfaces all the numbers
/// that aren't already on the timeline / video screen.
class MatchDetailsSheet extends StatelessWidget {
  const MatchDetailsSheet({
    required this.match,
    required this.rallies,
    required this.ballObservationCount,
    super.key,
  });

  final Match match;
  final List<Rally> rallies;
  final int ballObservationCount;

  @override
  Widget build(BuildContext context) {
    final totals = _aggregate(rallies);
    final totalTouches = totals.fold<int>(0, (a, b) => a + b);
    final theme = Theme.of(context);
    final dateFormat = DateFormat('d MMM y, HH:mm');
    final resolution = (match.frameWidth != null && match.frameHeight != null)
        ? '${match.frameWidth} × ${match.frameHeight}'
        : '—';
    final pipelineDuration = match.pipelineDurationMs != null
        ? formatDurationMs(match.pipelineDurationMs!)
        : '—';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          AppSpacing.m,
          AppSpacing.l,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              'Match details',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              match.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            _SectionHeader('Source'),
            _Stat(
              label: 'Imported',
              value: dateFormat.format(match.importedAt),
            ),
            _Stat(
              label: 'Video duration',
              value: formatDurationMs(match.durationMs),
            ),
            _Stat(label: 'Resolution', value: resolution),
            const SizedBox(height: AppSpacing.m),
            _SectionHeader('Pipeline run'),
            _Stat(
              label: 'Processed',
              value: match.processedAt != null
                  ? dateFormat.format(match.processedAt!)
                  : '—',
            ),
            _Stat(label: 'Duration', value: pipelineDuration),
            _Stat(
              label: 'Ball detections',
              value: '$ballObservationCount',
            ),
            _Stat(label: 'Rallies', value: '${rallies.length}'),
            const SizedBox(height: AppSpacing.m),
            _SectionHeader('Touches'),
            _Stat(label: 'Total', value: '$totalTouches'),
            _Stat(label: 'Home left', value: '${totals[0]}'),
            _Stat(label: 'Home right', value: '${totals[1]}'),
            _Stat(label: 'Away left', value: '${totals[2]}'),
            _Stat(label: 'Away right', value: '${totals[3]}'),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
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

List<int> _aggregate(List<Rally> rallies) {
  final counts = List<int>.filled(4, 0);
  for (final rally in rallies) {
    for (var i = 0; i < 4 && i < rally.touchCountBySlot.length; i++) {
      counts[i] += rally.touchCountBySlot[i];
    }
  }
  return counts;
}
