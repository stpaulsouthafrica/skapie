import 'package:flutter/material.dart';
import 'package:skapie/paint/paint_tokens.dart';

ThemeData paintTheme(PaintTokens tokens) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: tokens.accent,
        brightness: tokens.brightness,
      ).copyWith(
        primary: tokens.accent,
        onPrimary: tokens.onAccent,
        surface: tokens.canvas,
        onSurface: tokens.ink,
        onSurfaceVariant: tokens.muted,
        outline: tokens.hairline,
        outlineVariant: tokens.accent.withValues(alpha: 0.28),
        error: tokens.danger,
      );
  final text = TextTheme(
    labelLarge: TextStyle(
      color: tokens.ink,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
    ),
    labelSmall: TextStyle(
      color: tokens.muted,
      fontSize: 11,
      letterSpacing: 0.6,
    ),
    bodySmall: TextStyle(color: tokens.ink, fontSize: 12, height: 1.35),
    bodyMedium: TextStyle(color: tokens.ink, fontSize: 13, height: 1.35),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.canvas,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    hoverColor: tokens.accent.withValues(alpha: 0.08),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: tokens.panel,
      labelStyle: text.labelSmall,
      hintStyle: text.labelSmall,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PaintTokens.radiusField),
        borderSide: BorderSide(color: tokens.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PaintTokens.radiusField),
        borderSide: BorderSide(color: tokens.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PaintTokens.radiusField),
        borderSide: BorderSide(color: tokens.accent),
      ),
    ),
  );
}
