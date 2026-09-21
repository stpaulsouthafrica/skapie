import 'package:flutter/material.dart';
import 'package:skapie/paint/paint_tokens.dart';

class PaintScope extends InheritedWidget {
  const PaintScope({super.key, required this.tokens, required super.child});

  final PaintTokens tokens;

  static PaintTokens of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PaintScope>();
    return scope?.tokens ?? PaintTokens.dark();
  }

  @override
  bool updateShouldNotify(PaintScope oldWidget) => tokens != oldWidget.tokens;
}
