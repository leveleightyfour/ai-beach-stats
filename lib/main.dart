import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/theme/app_theme.dart';
import 'shared/providers/app_router.dart';
import 'shared/providers/documents_directory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docsDir = await getApplicationDocumentsDirectory();
  runApp(
    ProviderScope(
      overrides: [
        documentsDirectoryProvider.overrideWithValue(docsDir.path),
      ],
      child: const BeachStatsApp(),
    ),
  );
}

class BeachStatsApp extends ConsumerWidget {
  const BeachStatsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Beach Stats',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
