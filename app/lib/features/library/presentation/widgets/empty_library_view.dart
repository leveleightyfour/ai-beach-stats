import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

class EmptyLibraryView extends StatelessWidget {
  const EmptyLibraryView({super.key});

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
                Icons.sports_volleyball_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                'No matches yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Import a match video from your Photos library to start '
                'analysing rallies and touches.',
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
