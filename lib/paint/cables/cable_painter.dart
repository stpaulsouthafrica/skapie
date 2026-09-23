import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Screen-space cable. Geometry is decided elsewhere. This file only paints.
class PaintedCable {
  const PaintedCable({
    required this.from,
    required this.to,
    required this.color,
    this.preview = false,
    this.drawStart = 0,
    this.draw = 1,
    this.flash,
    this.flashAlpha = 1,
    this.arrival = 0,
    this.rest = 0,
    this.flow,
    this.flashTowardSource = false,
    this.arrivalAtStart = false,
    this.exitsRight = true,
    this.entersFromLeft = true,
    this.invalid = false,
    this.danglingStart = false,
    this.danglingEnd = false,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final bool preview;

  /// Where the visible stroke starts along the curve, 0 to 1.
  final double drawStart;

  /// Where the visible stroke ends along the curve, 0 to 1.
  final double draw;

  /// Position of the connect flash along the curve, 0 to 1.
  final double? flash;
  final double flashAlpha;

  /// Soft light sitting on the destination after the flash arrives.
  final double arrival;

  /// Resting glow along the cable after a one-shot flash, 0 to 1.
  final double rest;

  /// Looping pulse while this cable is feeding a run, 0 to 1.
  final double? flow;

  /// Activity flash travels from [to] back toward [from].
  final bool flashTowardSource;

  /// The arrival bloom sits on [from] instead of [to].
  final bool arrivalAtStart;

  /// A right-edge port leaves toward +x. A left-edge port leaves toward -x.
  final bool exitsRight;

  /// A left-edge port is approached from the left. A right-edge port from the right.
  final bool entersFromLeft;

  /// Dashed, in [color], with no flash. Nothing flows along it.
  final bool invalid;

  /// This end has nothing to plug into; it gets a cross.
  final bool danglingStart;
  final bool danglingEnd;
}

Path cableCurve(
  Offset start,
  Offset end,
  double zoom, {
  bool exitsRight = true,
  bool entersFromLeft = true,
}) {
  final span = (end.dx - start.dx).abs();
  final bend = (span * 0.45).clamp(28.0 * zoom, 160.0 * zoom);
  final leave = exitsRight ? bend : -bend;
  final approach = entersFromLeft ? -bend : bend;
  return Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      start.dx + leave,
      start.dy,
      end.dx + approach,
      end.dy,
      end.dx,
      end.dy,
    );
}

void paintCables(Canvas canvas, List<PaintedCable> cables, double zoom) {
  for (final cable in cables) {
    final path = cableCurve(
      cable.from,
      cable.to,
      zoom,
      exitsRight: cable.exitsRight,
      entersFromLeft: cable.entersFromLeft,
    );
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) {
      continue;
    }
    final metric = metrics.first;
    if (metric.length <= 0) {
      continue;
    }
    if (cable.invalid) {
      _invalid(canvas, cable, metric, zoom);
      continue;
    }
    final start = cable.drawStart.clamp(0.0, 1.0);
    final draw = cable.draw.clamp(0.0, 1.0);
    final shown = draw - start > 0.004
        ? metric.extractPath(metric.length * start, metric.length * draw)
        : null;
    if (shown != null) {
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
        towardEnd: !cable.flashTowardSource,
      );
    }
    if (cable.arrival > 0.01) {
      _settle(
        canvas,
        cable.arrivalAtStart ? cable.from : cable.to,
        cable.color,
        zoom,
        cable.arrival,
      );
    }
    if (cable.rest > 0.01 && shown != null) {
      final strength = cable.rest.clamp(0.0, 1.0);
      canvas.drawPath(
        shown,
        Paint()
          ..color = cable.color.withValues(alpha: 0.16 * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.2 * zoom
          ..strokeCap = StrokeCap.round
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 7 * zoom),
      );
      _settle(canvas, cable.from, cable.color, zoom, 0.5 * strength);
      _settle(canvas, cable.to, cable.color, zoom, 0.5 * strength);
    }
    final flow = cable.flow;
    if (flow != null) {
      _streak(canvas, metric, flow, cable.color, zoom, alpha: 0.72, wide: true);
    }
  }
}

void _invalid(
  Canvas canvas,
  PaintedCable cable,
  ui.PathMetric metric,
  double zoom,
) {
  final dash = 6.0 * zoom;
  final gap = 4.0 * zoom;
  final stroke = Paint()
    ..color = cable.color.withValues(alpha: cable.preview ? 0.8 : 0.95)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4 * zoom
    ..strokeCap = StrokeCap.round;
  for (var at = 0.0; at < metric.length; at += dash + gap) {
    final end = (at + dash).clamp(0.0, metric.length);
    canvas.drawPath(metric.extractPath(at, end), stroke);
  }
  final cross = 4.0 * zoom;
  for (final (dangling, at) in [
    (cable.danglingStart, cable.from),
    (cable.danglingEnd, cable.to),
  ]) {
    if (!dangling) {
      continue;
    }
    canvas.drawLine(
      at + Offset(-cross, -cross),
      at + Offset(cross, cross),
      stroke,
    );
    canvas.drawLine(
      at + Offset(-cross, cross),
      at + Offset(cross, -cross),
      stroke,
    );
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
  bool towardEnd = true,
}) {
  final dist = metric.length * t.clamp(0.0, 1.0);
  final trail = wide
      ? (metric.length * 0.16).clamp(18.0 * zoom, 90.0 * zoom)
      : (metric.length * 0.1).clamp(14.0 * zoom, 64.0 * zoom);
  final double start;
  final double end;
  if (towardEnd) {
    start = (dist - trail).clamp(0.0, dist);
    end = dist;
  } else {
    start = dist;
    end = (dist + trail).clamp(dist, metric.length);
  }
  if (end - start < 0.5) {
    return;
  }
  final extracted = metric.extractPath(start, end);
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
