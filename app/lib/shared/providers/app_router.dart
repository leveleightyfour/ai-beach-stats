import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analysis/presentation/analysis_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/review/presentation/review_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/library',
        builder: (context, state) => const LibraryScreen(),
      ),
      GoRoute(
        path: '/analysis/:matchId',
        builder: (context, state) => AnalysisScreen(
          matchId: state.pathParameters['matchId']!,
        ),
      ),
      GoRoute(
        path: '/review/:matchId',
        builder: (context, state) => ReviewScreen(
          matchId: state.pathParameters['matchId']!,
          initialRallyIndex: int.tryParse(
            state.uri.queryParameters['rally'] ?? '',
          ),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});
