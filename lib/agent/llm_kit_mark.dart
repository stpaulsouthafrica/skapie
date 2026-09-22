import 'package:flutter/material.dart';

/// Paint-simple diamond on [harness.llm] chrome. Not a chat bubble.
class LlmKitMark extends StatelessWidget {
  const LlmKitMark({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: LlmKitMarkPainter(color: color),
    );
  }
}

class LlmKitMarkPainter extends CustomPainter {
  const LlmKitMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 1)
      ..lineTo(size.width - 1, size.height / 2)
      ..lineTo(size.width / 2, size.height - 1)
      ..lineTo(1, size.height / 2)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.12
        ..strokeJoin = StrokeJoin.miter,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.32),
      Offset(size.width / 2, size.height * 0.68),
      Paint()
        ..color = color
        ..strokeWidth = size.shortestSide * 0.1,
    );
  }

  @override
  bool shouldRepaint(covariant LlmKitMarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
