import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/duration_format.dart';

class VideoControls extends StatelessWidget {
  const VideoControls({required this.controller, super.key});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final value = controller.value;
        final total = value.duration.inMilliseconds;
        final current = value.position.inMilliseconds;
        final fraction = total > 0
            ? (current / total).clamp(0.0, 1.0)
            : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              IconButton(
                iconSize: 32,
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () {
                  if (value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                formatDurationMs(current),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: Slider(
                  value: fraction.toDouble(),
                  onChanged: (v) {
                    final target = value.duration * v;
                    controller.seekTo(target);
                  },
                ),
              ),
              Text(
                formatDurationMs(total),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
