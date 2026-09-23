import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Length of the two-pulse flash on the ports an issue points at.
const Duration issueFlashDuration = Duration(milliseconds: 1000);

/// Two expanding rings on each port. [t] runs 0 to 1 over the whole flash.
class IssueFlashPainter extends CustomPainter {
  const IssueFlashPainter({
    required this.points,
    required this.t,
    required this.color,
    required this.zoom,
  });

  final List<Offset> points;
  final double t;
  final Color color;
  final double zoom;

  /// Strength of each pulse at [t]: two humps, the second starting halfway.
  static List<double> pulses(double t) {
    return [
      for (final start in const [0.0, 0.5])
        if (t >= start && t <= start + 0.5) (t - start) / 0.5,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final u in pulses(t)) {
      final eased = 1 - (1 - u) * (1 - u);
      final fade = 1 - u;
      for (final point in points) {
        canvas.drawCircle(
          point,
          (6 + 4 * fade) * zoom,
          Paint()
            ..color = color.withValues(alpha: 0.45 * fade)
            ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 5 * zoom),
        );
        canvas.drawCircle(
          point,
          (8 + 16 * eased) * zoom,
          Paint()
            ..color = color.withValues(alpha: 0.9 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * zoom,
        );
      }
    }
  }

  @override
  bool shouldRepaint(IssueFlashPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.color != color ||
        oldDelegate.zoom != zoom ||
        oldDelegate.points.length != points.length ||
        !_samePoints(oldDelegate.points, points);
  }

  bool _samePoints(List<Offset> a, List<Offset> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
