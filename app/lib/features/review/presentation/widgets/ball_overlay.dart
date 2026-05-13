import 'package:flutter/material.dart';

import '../../../analysis/domain/ball_observation.dart';

/// Finds the latest observation whose timestamp precedes [currentMs] and
/// is no older than [staleThresholdMs]. Returns null if no observation
/// is "active" at the current playback position.
///
/// Assumes [sorted] is ascending by `timestampMs`.
BallObservation? activeObservation(
  List<BallObservation> sorted,
  int currentMs, {
  int staleThresholdMs = 200,
}) {
  if (sorted.isEmpty) return null;

  var lo = 0;
  var hi = sorted.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (sorted[mid].timestampMs <= currentMs) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo == 0) return null;
  final candidate = sorted[lo - 1];
  if (currentMs - candidate.timestampMs > staleThresholdMs) return null;
  return candidate;
}

class BallOverlayPainter extends CustomPainter {
  BallOverlayPainter({
    required this.observation,
    required this.sourceSize,
  });

  final BallObservation? observation;
  final Size sourceSize;

  // High-contrast amber. Pulled out of the theme deliberately: the overlay
  // sits over arbitrary video footage where theme colours can't be relied
  // on to remain visible.
  static const _overlayColor = Color(0xFFFF9F1C);

  @override
  void paint(Canvas canvas, Size size) {
    final obs = observation;
    if (obs == null) return;
    if (sourceSize.width <= 0 || sourceSize.height <= 0) return;

    final sx = size.width / sourceSize.width;
    final sy = size.height / sourceSize.height;

    final rect = Rect.fromLTWH(
      obs.x * sx,
      obs.y * sy,
      obs.width * sx,
      obs.height * sy,
    );

    final boxPaint = Paint()
      ..color = _overlayColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, boxPaint);

    final label = '${(obs.confidence * 100).toStringAsFixed(0)}%';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padX = 6.0;
    const padY = 2.0;
    final labelRect = Rect.fromLTWH(
      rect.left,
      (rect.top - textPainter.height - padY * 2).clamp(0.0, size.height),
      textPainter.width + padX * 2,
      textPainter.height + padY * 2,
    );
    final labelPaint = Paint()..color = _overlayColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      labelPaint,
    );
    textPainter.paint(
      canvas,
      Offset(labelRect.left + padX, labelRect.top + padY),
    );
  }

  @override
  bool shouldRepaint(BallOverlayPainter oldDelegate) {
    return oldDelegate.observation != observation ||
        oldDelegate.sourceSize != sourceSize;
  }
}
