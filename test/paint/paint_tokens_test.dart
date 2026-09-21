import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/paint/paint.dart';

void main() {
  test('dark default is champagne gold on a solid canvas', () {
    final tokens = PaintTokens.dark();
    expect(tokens.brightness, Brightness.dark);
    expect(tokens.accent, PaintTokens.champagne);
    expect(tokens.canvas.a, 1);
    expect(tokens.panel.a, 1);
  });

  test('light paint theme reports light brightness', () {
    final theme = paintTheme(PaintTokens.light());
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(PaintTokens.light().canvas.a, 1);
  });
}
