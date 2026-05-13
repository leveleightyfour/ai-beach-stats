import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_spacing.dart';
import '../../analysis/domain/ball_observation.dart';
import '../../library/application/library_providers.dart';
import '../application/review_providers.dart';
import 'widgets/ball_overlay.dart';
import 'widgets/video_controls.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({
    required this.matchId,
    this.initialRallyIndex,
    super.key,
  });

  final String matchId;
  final int? initialRallyIndex;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  late final Future<VideoPlayerController?> _controllerFuture;
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _controllerFuture = _initController();
  }

  Future<VideoPlayerController?> _initController() async {
    final match = await ref
        .read(matchRepositoryProvider)
        .findById(widget.matchId);
    if (match == null) return null;
    final controller = VideoPlayerController.file(File(match.videoPath));
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return null;
    }
    _controller = controller;
    return controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchByIdProvider(widget.matchId));
    return Scaffold(
      appBar: AppBar(title: Text(match.valueOrNull?.title ?? 'Review')),
      body: FutureBuilder<VideoPlayerController?>(
        future: _controllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final controller = snapshot.data;
          if (controller == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.l),
                child: Text('Match not found.'),
              ),
            );
          }
          return _ReviewBody(
            matchId: widget.matchId,
            controller: controller,
          );
        },
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({required this.matchId, required this.controller});

  final String matchId;
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observations = ref.watch(matchBallObservationsProvider(matchId));
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: Stack(
              children: [
                VideoPlayer(controller),
                Positioned.fill(
                  child: _BallOverlay(
                    controller: controller,
                    observations: observations.valueOrNull ??
                        const <BallObservation>[],
                  ),
                ),
              ],
            ),
          ),
          VideoControls(controller: controller),
          _ObservationsFooter(observations: observations),
        ],
      ),
    );
  }
}

class _BallOverlay extends StatelessWidget {
  const _BallOverlay({required this.controller, required this.observations});

  final VideoPlayerController controller;
  final List<BallObservation> observations;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final value = controller.value;
        final currentMs = value.position.inMilliseconds;
        final active = activeObservation(observations, currentMs);
        return CustomPaint(
          painter: BallOverlayPainter(
            observation: active,
            sourceSize: value.size,
          ),
        );
      },
    );
  }
}

class _ObservationsFooter extends StatelessWidget {
  const _ObservationsFooter({required this.observations});

  final AsyncValue<List<BallObservation>> observations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = observations.when(
      data: (list) => '${list.length} ball detections',
      loading: () => 'Loading detections…',
      error: (error, _) => 'Failed to load detections: $error',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s,
        0,
        AppSpacing.s,
        AppSpacing.s,
      ),
      child: Text(
        body,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
