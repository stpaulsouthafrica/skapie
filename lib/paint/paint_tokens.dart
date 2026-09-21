import 'package:flutter/material.dart';

/// Visual tokens only. Scene, kits, and the agent harness do not live here.
class PaintTokens {
  const PaintTokens({
    required this.brightness,
    required this.accent,
    required this.canvas,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.danger,
    required this.onAccent,
  });

  final Brightness brightness;
  final Color accent;
  final Color canvas;
  final Color panel;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color danger;
  final Color onAccent;

  static const Color champagne = Color(0xFFC4A46A);
  static const double radiusField = 10;
  static const double radiusPanel = 16;
  static const double space = 8;

  bool get isDark => brightness == Brightness.dark;

  factory PaintTokens.dark({Color accent = champagne}) {
    const ink = Color(0xFFF4EFE6);
    return PaintTokens(
      brightness: Brightness.dark,
      accent: accent,
      canvas: const Color(0xFF0C0C0E),
      panel: const Color(0xFF161618),
      ink: ink,
      muted: ink.withValues(alpha: 0.62),
      hairline: accent.withValues(alpha: 0.35),
      danger: const Color(0xFFB85C5C),
      onAccent: const Color(0xFF1A1408),
    );
  }

  factory PaintTokens.light({Color accent = champagne}) {
    const ink = Color(0xFF1A1814);
    return PaintTokens(
      brightness: Brightness.light,
      accent: accent,
      canvas: const Color(0xFFF7F4EE),
      panel: const Color(0xFFFFFFFF),
      ink: ink,
      muted: ink.withValues(alpha: 0.62),
      hairline: accent.withValues(alpha: 0.45),
      danger: const Color(0xFFB85C5C),
      onAccent: const Color(0xFF1A1408),
    );
  }
}
