import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/library_providers.dart';
import '../application/match_importer.dart';
import '../domain/match.dart';
import 'widgets/empty_library_view.dart';
import 'widgets/match_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<void>>(matchImporterProvider, (prev, next) {
      final error = next.error;
      if (error != null && prev?.error != error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $error')),
        );
      }
    });

    final matchesAsync = ref.watch(matchesListProvider);
    final isImporting = ref.watch(matchImporterProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      body: matchesAsync.when(
        skipLoadingOnReload: true,
        data: (matches) => matches.isEmpty
            ? const EmptyLibraryView()
            : _MatchGrid(matches: matches),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Text("Couldn't load matches: $error"),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isImporting ? null : () => _onImport(context, ref),
        icon: isImporting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(isImporting ? 'Importing…' : 'Import match'),
      ),
    );
  }

  Future<void> _onImport(BuildContext context, WidgetRef ref) async {
    final match = await ref
        .read(matchImporterProvider.notifier)
        .importFromGallery();
    if (match != null && context.mounted) {
      context.go('/analysis/${match.id}');
    }
  }
}

class _MatchGrid extends StatelessWidget {
  const _MatchGrid({required this.matches});

  final List<Match> matches;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.xxl,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: 220,
        crossAxisSpacing: AppSpacing.s,
        mainAxisSpacing: AppSpacing.s,
      ),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final match = matches[index];
        return MatchTile(
          match: match,
          onTap: () => context.go('/analysis/${match.id}'),
        );
      },
    );
  }
}
