import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Synchronous accessor for the app's documents directory path.
///
/// Overridden in `main()` before `runApp()` with the resolved path so
/// widgets and providers can read it without an async hop. Match records
/// store paths relative to this directory (iOS app containers rotate
/// their UUID across rebuilds, so absolute paths go stale).
final documentsDirectoryProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'documentsDirectoryProvider must be overridden in main() before runApp().',
  );
});
