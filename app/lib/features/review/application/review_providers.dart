import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/database/app_database_provider.dart';
import '../../analysis/domain/ball_observation.dart';
import '../data/review_repository.dart';

part 'review_providers.g.dart';

@Riverpod(keepAlive: true)
ReviewRepository reviewRepository(ReviewRepositoryRef ref) {
  return ReviewRepository(ref.watch(appDatabaseProvider));
}

@riverpod
Stream<List<BallObservation>> matchBallObservations(
  MatchBallObservationsRef ref,
  String matchId,
) {
  return ref.watch(reviewRepositoryProvider).watchObservations(matchId);
}
