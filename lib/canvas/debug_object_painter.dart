import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/scene/scene_object.dart';

/// Temporary world-space rectangles for scene objects. Not a widget registry.
final class DebugObjectPainter extends CustomPainter {
  DebugObjectPainter({
    required this.camera,
    required this.objects,
    required this.fillColor,
    required this.strokeColor,
  });

  final CanvasCamera camera;
  final List<SceneObject> objects;
  final Color fillColor;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = fillColor;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final ordered = [
      for (final object in objects)
        if (object.visible) object,
    ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    for (final object in ordered) {
      final topLeft = worldToScreen(Offset(object.x, object.y), size, camera);
      final rect = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        object.width * camera.zoom,
        object.height * camera.zoom,
      );
      canvas
        ..save()
        ..translate(rect.center.dx, rect.center.dy)
        ..rotate(object.rotation)
        ..translate(-rect.center.dx, -rect.center.dy)
        ..drawRect(rect, fill)
        ..drawRect(rect, stroke)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(covariant DebugObjectPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.objects != objects ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor;
  }
}
