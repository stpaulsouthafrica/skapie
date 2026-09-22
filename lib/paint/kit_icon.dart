import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit_mark.dart';

enum KitIconKind {
  llm,
  text,
  conversation,
  box,
  button,
  tool,
  settings,
  link,
  unlink,
}

class KitIcon extends StatelessWidget {
  const KitIcon({
    super.key,
    required this.kind,
    required this.color,
    required this.size,
  });

  final KitIconKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (kind == KitIconKind.llm) {
      return LlmKitMark(color: color, size: size);
    }
    return CustomPaint(
      size: Size.square(size),
      painter: _KitIconPainter(kind: kind, color: color),
    );
  }
}

class _KitIconPainter extends CustomPainter {
  const _KitIconPainter({required this.kind, required this.color});

  final KitIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.1;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inset = size.shortestSide * 0.16;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    switch (kind) {
      case KitIconKind.conversation:
        final top = Rect.fromLTWH(
          rect.left,
          rect.top,
          rect.width * 0.72,
          rect.height * 0.42,
        );
        final bottom = Rect.fromLTWH(
          rect.left + rect.width * 0.28,
          rect.top + rect.height * 0.5,
          rect.width * 0.72,
          rect.height * 0.42,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(top, Radius.circular(rect.height * 0.2)),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bottom, Radius.circular(rect.height * 0.2)),
          paint,
        );
      case KitIconKind.text:
        final left = rect.left;
        final right = rect.right;
        for (var i = 0; i < 3; i++) {
          final y = rect.top + rect.height * (0.22 + i * 0.28);
          canvas.drawLine(Offset(left, y), Offset(right, y), paint);
        }
      case KitIconKind.box:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.18)),
          paint,
        );
      case KitIconKind.button:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.height)),
          paint,
        );
      case KitIconKind.tool:
        canvas.drawCircle(rect.center, rect.shortestSide * 0.28, paint);
        canvas.drawLine(
          rect.center + Offset(rect.width * 0.12, rect.height * 0.12),
          rect.bottomRight,
          paint,
        );
      case KitIconKind.settings:
        for (var i = 0; i < 3; i++) {
          final y = rect.top + rect.height * (0.22 + i * 0.28);
          final knobX = rect.left + rect.width * (i == 1 ? 0.7 : 0.32);
          final gap = rect.width * 0.18;
          canvas.drawLine(Offset(rect.left, y), Offset(knobX - gap, y), paint);
          canvas.drawLine(Offset(knobX + gap, y), Offset(rect.right, y), paint);
          canvas.drawCircle(
            Offset(knobX, y),
            stroke * 1.5,
            Paint()
              ..color = color
              ..style = PaintingStyle.fill,
          );
        }
      case KitIconKind.link:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: rect.center,
              width: rect.width * 0.72,
              height: rect.height * 0.42,
            ),
            Radius.circular(rect.height),
          ),
          paint,
        );
      case KitIconKind.unlink:
        canvas.drawLine(rect.topLeft, rect.bottomRight, paint);
        canvas.drawLine(rect.topRight, rect.bottomLeft, paint);
      case KitIconKind.llm:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _KitIconPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

KitIconKind kitIconForKitId(String? kitId) {
  if (kitId == null || kitId.isEmpty) {
    return KitIconKind.box;
  }
  if (kitId == 'harness.llm') {
    return KitIconKind.llm;
  }
  if (kitId == 'harness.conversation') {
    return KitIconKind.conversation;
  }
  if (kitId.startsWith('tools.')) {
    return KitIconKind.tool;
  }
  if (kitId == 'board.text') {
    return KitIconKind.text;
  }
  if (kitId == 'board.button') {
    return KitIconKind.button;
  }
  return KitIconKind.box;
}
