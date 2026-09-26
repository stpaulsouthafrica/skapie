import 'package:flutter/material.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/paint/paint_tokens.dart';

/// Colors the Full Screen context assembly: headings, sources, and one tone
/// per provenance so instructions and data read apart at a glance.
TextSpan highlightContextAssembly(
  String source,
  PaintTokens tokens, {
  double fontSize = 11,
}) {
  final palette = _AssemblyPalette.of(tokens, fontSize);
  final headings = {
    contextAssemblyTitle,
    for (final layer in ContextLayer.values) layer.label,
    contextAssemblyExcludedHeading,
  };
  final instructions = {
    ContextProvenance.userTask.label,
    ContextProvenance.boardInstruction.label,
  };
  final repository = ContextProvenance.repositoryText.label;
  final summary = ContextProvenance.compactedSummary.label;

  final spans = <InlineSpan>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final newline = i == lines.length - 1 ? '' : '\n';
    if (line.trim().isEmpty) {
      spans.add(TextSpan(text: line + newline, style: palette.plain));
      continue;
    }
    if (headings.contains(line)) {
      spans.add(
        TextSpan(
          text: line + newline,
          style: line == contextAssemblyTitle
              ? palette.title
              : line == contextAssemblyExcludedHeading
              ? palette.excluded
              : palette.heading,
        ),
      );
      continue;
    }
    final item = _itemLine.matchAsPrefix(line);
    if (item != null) {
      final provenance = item.group(3)!;
      final color = instructions.contains(provenance)
          ? palette.instruction
          : provenance == repository
          ? palette.repository
          : provenance == summary
          ? palette.summary
          : palette.data;
      spans.add(TextSpan(text: '${item.group(1)}. ', style: palette.plain));
      spans.add(
        TextSpan(
          text: '${item.group(2)}$contextAssemblyItemSeparator',
          style: palette.source,
        ),
      );
      spans.add(TextSpan(text: provenance, style: palette.tone(color)));
      spans.add(TextSpan(text: '${item.group(4) ?? ''}$newline', style: palette.plain));
      continue;
    }
    final detail = _detailLine.matchAsPrefix(line);
    if (detail != null) {
      spans.add(TextSpan(text: '   ${detail.group(1)}: ', style: palette.prefix));
      spans.add(
        TextSpan(
          text: '${detail.group(2)}$newline',
          style: detail.group(1) == 'trust' ? palette.note : palette.plain,
        ),
      );
      continue;
    }
    final exclusion = _exclusionLine.matchAsPrefix(line);
    if (exclusion != null) {
      spans.add(
        TextSpan(
          text: '${exclusion.group(1)}$contextAssemblyItemSeparator',
          style: palette.source,
        ),
      );
      spans.add(TextSpan(text: '${exclusion.group(2)}$newline', style: palette.note));
      continue;
    }
    spans.add(TextSpan(text: line + newline, style: palette.plain));
  }
  return TextSpan(children: spans, style: palette.plain);
}

final _itemLine = RegExp(r'^(\d+)\. (.+?) — (.+?)( · Truncated)?$');
final _detailLine = RegExp(r'^   (reason|trust|text): (.*)$');
final _exclusionLine = RegExp(r'^([^\s].*?) — (.*)$');

class _AssemblyPalette {
  const _AssemblyPalette({
    required this.plain,
    required this.note,
    required this.prefix,
    required this.source,
    required this.title,
    required this.heading,
    required this.excluded,
    required this.instruction,
    required this.data,
    required this.repository,
    required this.summary,
  });

  factory _AssemblyPalette.of(PaintTokens tokens, double fontSize) {
    final dark = tokens.isDark;
    TextStyle style(Color color, {FontWeight? weight, FontStyle? fontStyle}) =>
        TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1.4,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier'],
          fontWeight: weight,
          fontStyle: fontStyle,
        );
    return _AssemblyPalette(
      plain: style(tokens.ink),
      note: style(tokens.muted),
      prefix: style(tokens.muted),
      source: style(tokens.ink, weight: FontWeight.w600),
      title: style(tokens.accent, weight: FontWeight.w700),
      heading: style(tokens.ink, weight: FontWeight.w600),
      excluded: style(dark ? const Color(0xFFE0B15A) : const Color(0xFF8A5A12), weight: FontWeight.w600),
      instruction: tokens.accent,
      data: dark ? const Color(0xFF8EB7E0) : const Color(0xFF2A5F8A),
      repository: dark ? const Color(0xFFE0B15A) : const Color(0xFF8A5A12),
      summary: dark ? const Color(0xFFC9A4D4) : const Color(0xFF6B4A86),
    );
  }

  final TextStyle plain;
  final TextStyle note;
  final TextStyle prefix;
  final TextStyle source;
  final TextStyle title;
  final TextStyle heading;
  final TextStyle excluded;
  final Color instruction;
  final Color data;
  final Color repository;
  final Color summary;

  TextStyle tone(Color color) => TextStyle(
    color: color,
    fontSize: plain.fontSize,
    height: plain.height,
    fontFamily: plain.fontFamily,
    fontFamilyFallback: plain.fontFamilyFallback,
    fontWeight: FontWeight.w600,
  );
}
