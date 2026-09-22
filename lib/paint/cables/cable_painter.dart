import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Screen-space cable. Geometry is decided elsewhere. This file only paints.
class PaintedCable {
  const PaintedCable({
    required this.from,
    required this.to,
    required this.color,
    this.preview = false,
    this.draw = 1,
    this.flash,
    this.flashAlpha = 1,
    this.arrival = 0,
    this.flow,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final bool preview;

  /// How much of the curve is laid down, 0 to 1.
  final double draw;

  /// Position of the connect flash along the curve, 0 to 1.
  final double? flash;
  final double flashAlpha;

  /// Soft light sitting on the destination after the flash arrives.
  final double arrival;

  /// Looping pulse while this cable is feeding a run, 0 to 1.
  final double? flow;
}

Path cableCurve(Offset start, Offset end, double zoom) {
  final span = (end.dx - start.dx).abs();
  final bend = (span * 0.45).clamp(28.0 * zoom, 160.0 * zoom);
  return Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(start.dx + bend, start.dy, end.dx - bend, end.dy, end.dx, end.dy);
}

void paintCables(Canvas canvas, List<PaintedCable> cables, double zoom) {
  for (final cable in cables) {
    final path = cableCurve(cable.from, cable.to, zoom);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) {
      continue;
    }
    final metric = metrics.first;
    if (metric.length <= 0) {
      continue;
    }
    final draw = cable.draw.clamp(0.0, 1.0);
    if (draw > 0.004) {
      final shown = metric.extractPath(0, metric.length * draw);
      canvas.drawPath(
        shown,
        Paint()
          ..color = cable.color.withValues(alpha: cable.preview ? 0.22 : 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.5 * zoom
          ..strokeCap = StrokeCap.round
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 3.5 * zoom),
      );
      canvas.drawPath(
        shown,
        Paint()
          ..color = cable.color.withValues(alpha: cable.preview ? 0.9 : 1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * zoom
          ..strokeCap = StrokeCap.round,
      );
    }
    final flash = cable.flash;
    if (flash != null && cable.flashAlpha > 0.01) {
      _streak(
        canvas,
        metric,
        flash,
        cable.color,
        zoom,
        alpha: cable.flashAlpha,
        wide: false,
      );
    }
    if (cable.arrival > 0.01) {
      _settle(canvas, cable.to, cable.color, zoom, cable.arrival);
    }
    final flow = cable.flow;
    if (flow != null) {
      _streak(canvas, metric, flow, cable.color, zoom, alpha: 0.72, wide: true);
    }
  }
}

void _streak(
  Canvas canvas,
  ui.PathMetric metric,
  double t,
  Color color,
  double zoom, {
  required double alpha,
  required bool wide,
}) {
  final dist = metric.length * t.clamp(0.0, 1.0);
  final trail = wide
      ? (metric.length * 0.16).clamp(18.0 * zoom, 90.0 * zoom)
      : (metric.length * 0.1).clamp(14.0 * zoom, 64.0 * zoom);
  final extracted = metric.extractPath((dist - trail).clamp(0.0, dist), dist);
  canvas.drawPath(
    extracted,
    Paint()
      ..color = color.withValues(alpha: (wide ? 0.4 : 0.7) * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (wide ? 2.4 : 2.1) * zoom
      ..strokeCap = StrokeCap.round
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 2.2 * zoom),
  );
  canvas.drawPath(
    extracted,
    Paint()
      ..color = const Color(0xFFFFF8EC)
          .withValues(alpha: (wide ? 0.55 : 0.92) * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * zoom
      ..strokeCap = StrokeCap.round,
  );
}

void _settle(
  Canvas canvas,
  Offset at,
  Color color,
  double zoom,
  double amount,
) {
  final strength = amount.clamp(0.0, 1.0);
  canvas.drawCircle(
    at,
    (6.5 + 4 * strength) * zoom,
    Paint()
      ..color = color.withValues(alpha: 0.42 * strength)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 7 * zoom),
  );
  canvas.drawCircle(
    at,
    1.6 * zoom,
    Paint()..color = const Color(0xFFFFF8EC).withValues(alpha: 0.8 * strength),
  );
}
