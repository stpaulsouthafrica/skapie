import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_camera.dart';

/// World-space dot grid plus an origin marker at (0, 0).
final class CanvasGridPainter extends CustomPainter {
  CanvasGridPainter({
    required this.camera,
    required this.dotColor,
    required this.originColor,
  });

  final CanvasCamera camera;
  final Color dotColor;
  final Color originColor;

  static const _baseSpacing = 32.0;

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft = screenToWorld(Offset.zero, size, camera);
    final bottomRight = screenToWorld(
      Offset(size.width, size.height),
      size,
      camera,
    );
    final spacing = _spacingForZoom(camera.zoom);
    _paintDots(canvas, size, topLeft, bottomRight, spacing);
    _paintOrigin(canvas, size);
  }

  double _spacingForZoom(double zoom) {
    var spacing = _baseSpacing;
    while (spacing * zoom < 18) {
      spacing *= 2;
    }
    while (spacing * zoom > 56 && spacing > 8) {
      spacing /= 2;
    }
    return spacing;
  }

  void _paintDots(
    Canvas canvas,
    Size size,
    Offset topLeft,
    Offset bottomRight,
    double spacing,
  ) {
    final startX = (topLeft.dx / spacing).floor() * spacing;
    final startY = (topLeft.dy / spacing).floor() * spacing;
    final cols = ((bottomRight.dx - startX) / spacing).ceil() + 1;
    final rows = ((bottomRight.dy - startY) / spacing).ceil() + 1;
    if (cols * rows > 16000) {
      return;
    }

    final paint = Paint()..color = dotColor;
    const radius = 1.15;
    for (var i = 0; i < cols; i++) {
      final x = startX + i * spacing;
      for (var j = 0; j < rows; j++) {
        final y = startY + j * spacing;
        canvas.drawCircle(
          worldToScreen(Offset(x, y), size, camera),
          radius,
          paint,
        );
      }
    }
  }

  void _paintOrigin(Canvas canvas, Size size) {
    final origin = worldToScreen(Offset.zero, size, camera);
    final paint = Paint()
      ..color = originColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas
      ..drawCircle(origin, 7, paint)
      ..drawLine(origin.translate(-11, 0), origin.translate(11, 0), paint)
      ..drawLine(origin.translate(0, -11), origin.translate(0, 11), paint);
  }

  @override
  bool shouldRepaint(covariant CanvasGridPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.originColor != originColor;
  }
}
