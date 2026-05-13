import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/duration_format.dart';
import '../../../analysis/domain/rally.dart';

class RallyTimeline extends StatelessWidget {
  const RallyTimeline({
    required this.rallies,
    required this.onSeek,
    super.key,
  });

  final List<Rally> rallies;
  final void Function(int timestampMs) onSeek;

  @override
  Widget build(BuildContext context) {
    if (rallies.isEmpty) {
      return const _EmptyTimeline();
    }
    return ListView.separated(
      itemCount: rallies.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: AppSpacing.l),
      itemBuilder: (context, index) {
        final rally = rallies[index];
        return _RallyRow(
          rally: rally,
          onTap: () => onSeek(rally.startTimestampMs),
        );
      },
    );
  }
}

class _RallyRow extends StatelessWidget {
  const _RallyRow({required this.rally, required this.onTap});

  final Rally rally;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tabularBody = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      leading: _RallyNumberBadge(index: rally.rallyIndex + 1),
      title: Text(
        '${formatDurationMs(rally.startTimestampMs)}'
        '  —  '
        '${formatDurationMs(rally.endTimestampMs)}',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatDurationMs(rally.durationMs)} '
              '·  ${rally.totalTouches} '
              '${rally.totalTouches == 1 ? "touch" : "touches"}',
              style: tabularBody,
            ),
            if (rally.totalTouches > 0) ...[
              const SizedBox(height: 2),
              _SlotCounts(counts: rally.touchCountBySlot),
            ],
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _RallyNumberBadge extends StatelessWidget {
  const _RallyNumberBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.s),
      ),
      child: Text(
        '$index',
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SlotCounts extends StatelessWidget {
  const _SlotCounts({required this.counts});

  // [homeLeft, homeRight, awayLeft, awayRight] — matches PlayerSlot.index.
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labels = ['HL', 'HR', 'AL', 'AR'];
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return DefaultTextStyle(
      style: mutedStyle ?? const TextStyle(),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s),
            RichText(
              text: TextSpan(
                style: mutedStyle,
                children: [
                  TextSpan(text: '${labels[i]} '),
                  TextSpan(
                    text: '${counts[i]}',
                    style: TextStyle(
                      color: counts[i] > 0
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: counts[i] > 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                      fontFeatures:
                          const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                'No rallies detected',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Try a lower detection threshold or longer footage to '
                'find rally spans.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
