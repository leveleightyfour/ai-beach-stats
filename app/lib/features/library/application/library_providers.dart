import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/database/app_database_provider.dart';
import '../data/match_repository.dart';
import '../domain/match.dart';

part 'library_providers.g.dart';

@Riverpod(keepAlive: true)
MatchRepository matchRepository(MatchRepositoryRef ref) {
  return MatchRepository(ref.watch(appDatabaseProvider));
}

@riverpod
Stream<List<Match>> matchesList(MatchesListRef ref) {
  return ref.watch(matchRepositoryProvider).watchAll();
}
