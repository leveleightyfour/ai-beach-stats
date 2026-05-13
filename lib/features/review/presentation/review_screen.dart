import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/documents_directory.dart';
import '../../analysis/application/analysis_providers.dart';
import '../../analysis/domain/ball_observation.dart';
import '../../analysis/domain/rally.dart';
import '../../library/application/library_providers.dart';
import '../application/review_providers.dart';
import 'widgets/ball_overlay.dart';
import 'widgets/rally_timeline.dart';
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
    final docsDir = ref.read(documentsDirectoryProvider);
    final absoluteVideoPath = p.join(docsDir, match.videoPath);
    final controller = VideoPlayerController.file(File(absoluteVideoPath));
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

  Future<void> _onReprocess() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Re-process match?'),
        content: const Text(
          'Existing rallies, touches, and ball detections will be replaced '
          'when the pipeline finishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Re-process'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(analysisRepositoryProvider)
        .resetResults(widget.matchId);
    ref.invalidate(analysisControllerProvider(widget.matchId));
    if (!mounted) return;
    context.pushReplacement('/analysis/${widget.matchId}');
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchByIdProvider(widget.matchId));
    return Scaffold(
      appBar: AppBar(
        title: Text(match.valueOrNull?.title ?? 'Review'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-process',
            onPressed: _onReprocess,
          ),
        ],
      ),
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
    final observationsAsync = ref.watch(
      matchBallObservationsProvider(matchId),
    );
    final ralliesAsync = ref.watch(matchRalliesProvider(matchId));

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
                    observations: observationsAsync.valueOrNull ??
                        const <BallObservation>[],
                  ),
                ),
              ],
            ),
          ),
          VideoControls(controller: controller),
          const Divider(height: 1),
          _TimelineHeader(
            rallies: ralliesAsync,
            observations: observationsAsync,
          ),
          Expanded(
            child: ralliesAsync.when(
              skipLoadingOnReload: true,
              data: (rallies) => RallyTimeline(
                rallies: rallies,
                onSeek: (ms) => controller.seekTo(
                  Duration(milliseconds: ms),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  child: Text("Couldn't load rallies: $error"),
                ),
              ),
            ),
          ),
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

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.rallies,
    required this.observations,
  });

  final AsyncValue<List<Rally>> rallies;
  final AsyncValue<List<BallObservation>> observations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rallyCount = rallies.valueOrNull?.length ?? 0;
    final observationCount = observations.valueOrNull?.length ?? 0;
    final detail =
        '$rallyCount ${rallyCount == 1 ? "rally" : "rallies"}'
        '  ·  $observationCount ball detections';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.xs,
      ),
      child: Text(
        detail,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
