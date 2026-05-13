// Dart-side facade over the Pigeon-generated MLPipeline bindings.
//
// Imports `ml_pipeline.g.dart`, which is produced by running:
//   dart run pigeon --input pigeons/ml_pipeline.dart

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'ml_pipeline.g.dart';

/// A live pipeline session: the sessionId, a broadcast stream of events,
/// and a `cancel` hook that tears it down on both sides.
class PipelineSession {
  PipelineSession({
    required this.sessionId,
    required this.events,
    required this.cancel,
  });

  final String sessionId;
  final Stream<PipelineEvent> events;
  final Future<void> Function() cancel;
}

/// Singleton facade. Construct once per app (via the Riverpod provider) so
/// only one [MLPipelineEventListener] is registered with Pigeon — Pigeon's
/// setUp replaces any previous handler.
class MLPipelineFacade {
  MLPipelineFacade({
    MLPipelineHostApi? hostApi,
    Uuid? uuid,
  })  : _hostApi = hostApi ?? MLPipelineHostApi(),
        _uuid = uuid ?? const Uuid() {
    MLPipelineEventListener.setUp(_FacadeListener(_routeEvent));
  }

  final MLPipelineHostApi _hostApi;
  final Uuid _uuid;
  final Map<String, StreamController<PipelineEvent>> _controllers = {};

  Future<PipelineSession> startSession({
    required String matchId,
    required String videoPath,
    required PipelineConfig config,
  }) async {
    final sessionId = _uuid.v4();
    final controller = StreamController<PipelineEvent>.broadcast();
    _controllers[sessionId] = controller;

    try {
      await _hostApi.startProcessing(sessionId, matchId, videoPath, config);
    } catch (error) {
      _controllers.remove(sessionId);
      await controller.close();
      rethrow;
    }

    return PipelineSession(
      sessionId: sessionId,
      events: controller.stream,
      cancel: () => _teardown(sessionId),
    );
  }

  Future<void> _teardown(String sessionId) async {
    final controller = _controllers.remove(sessionId);
    if (controller == null) return;
    try {
      await _hostApi.cancel(sessionId);
    } finally {
      await controller.close();
    }
  }

  void _routeEvent(PipelineEvent event) {
    final controller = _controllers[event.sessionId];
    if (controller == null || controller.isClosed) return;
    controller.add(event);
    if (event.type == PipelineEventType.completion ||
        event.type == PipelineEventType.error ||
        event.type == PipelineEventType.cancelled) {
      // Terminal events: detach but leave the controller open long enough
      // for late subscribers (e.g. screens awaiting `Future.first`).
      _controllers.remove(event.sessionId);
      scheduleMicrotask(controller.close);
    }
  }
}

class _FacadeListener extends MLPipelineEventListener {
  _FacadeListener(this._onEvent);
  final void Function(PipelineEvent) _onEvent;

  @override
  void onPipelineEvent(PipelineEvent event) => _onEvent(event);
}
