import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({
    required this.matchId,
    this.initialRallyIndex,
    super.key,
  });

  final String matchId;
  final int? initialRallyIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Center(
        child: Text(
          'Review — rallies + overlay for $matchId'
          '${initialRallyIndex != null ? ' (rally $initialRallyIndex)' : ''}',
        ),
      ),
    );
  }
}
