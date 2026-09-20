import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/scene/scene_node.dart';

/// Temporary world-space rectangles for scene nodes. Not a widget registry.
final class DebugNodePainter extends CustomPainter {
  DebugNodePainter({
    required this.camera,
    required this.nodes,
    required this.fillColor,
    required this.strokeColor,
  });

  final CanvasCamera camera;
  final List<SceneNode> nodes;
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
      for (final node in nodes)
        if (node.visible) node,
    ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    for (final node in ordered) {
      final topLeft = worldToScreen(Offset(node.x, node.y), size, camera);
      final rect = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        node.width * camera.zoom,
        node.height * camera.zoom,
      );
      canvas
        ..save()
        ..translate(rect.center.dx, rect.center.dy)
        ..rotate(node.rotation)
        ..translate(-rect.center.dx, -rect.center.dy)
        ..drawRect(rect, fill)
        ..drawRect(rect, stroke)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(covariant DebugNodePainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.nodes != nodes ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor;
  }
}
