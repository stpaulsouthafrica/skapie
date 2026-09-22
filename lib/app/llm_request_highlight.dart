import 'package:flutter/material.dart';
import 'package:skapie/paint/paint_tokens.dart';

/// Colors an HTTP request preview: method, headers, and JSON.
TextSpan highlightLlmRequest(
  String source,
  PaintTokens tokens, {
  double fontSize = 11,
}) {
  final palette = _RequestPalette.of(tokens, fontSize);
  final spans = <InlineSpan>[];
  final lines = source.split('\n');
  var json = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final newline = i == lines.length - 1 ? '' : '\n';
    final trimmed = line.trimLeft();
    if (!json && (trimmed.startsWith('{') || trimmed.startsWith('['))) {
      json = true;
    }
    if (json) {
      spans.addAll(_jsonSpans(line, palette));
      if (newline.isNotEmpty) {
        spans.add(TextSpan(text: newline, style: palette.plain));
      }
      continue;
    }
    final method = _method.matchAsPrefix(line);
    if (method != null) {
      spans.add(TextSpan(text: method.group(1), style: palette.method));
      spans.add(TextSpan(text: method.group(2)! + newline, style: palette.url));
      continue;
    }
    final header = _header.matchAsPrefix(line);
    if (header != null) {
      spans.add(TextSpan(text: '${header.group(1)}: ', style: palette.header));
      spans.add(
        TextSpan(text: '${header.group(2)}$newline', style: palette.plain),
      );
      continue;
    }
    spans.add(TextSpan(text: line + newline, style: palette.note));
  }
  return TextSpan(children: spans, style: palette.plain);
}

final _method = RegExp(r'^(POST|GET|PUT|PATCH|DELETE)( .*)$');
final _header = RegExp(r'^([A-Za-z][A-Za-z0-9\-]*): (.*)$');

class _RequestPalette {
  const _RequestPalette({
    required this.plain,
    required this.note,
    required this.method,
    required this.url,
    required this.header,
    required this.punct,
    required this.key,
    required this.string,
    required this.number,
    required this.keyword,
  });

  factory _RequestPalette.of(PaintTokens tokens, double fontSize) {
    final dark = tokens.isDark;
    TextStyle style(Color color) => TextStyle(
      color: color,
      fontSize: fontSize,
      height: 1.4,
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
    );
    return _RequestPalette(
      plain: style(tokens.ink),
      note: style(tokens.muted),
      method: style(tokens.accent),
      url: style(dark ? const Color(0xFF8EB7E0) : const Color(0xFF2A5F8A)),
      header: style(tokens.muted),
      punct: style(tokens.muted),
      key: style(tokens.accent),
      string: style(dark ? const Color(0xFFC8D6A8) : const Color(0xFF3D6B4F)),
      number: style(dark ? const Color(0xFFE0B15A) : const Color(0xFF8A5A12)),
      keyword: style(dark ? const Color(0xFFC9A4D4) : const Color(0xFF6B4A86)),
    );
  }

  final TextStyle plain;
  final TextStyle note;
  final TextStyle method;
  final TextStyle url;
  final TextStyle header;
  final TextStyle punct;
  final TextStyle key;
  final TextStyle string;
  final TextStyle number;
  final TextStyle keyword;
}

List<InlineSpan> _jsonSpans(String line, _RequestPalette palette) {
  final spans = <InlineSpan>[];
  var i = 0;
  while (i < line.length) {
    final char = line[i];
    if (char == ' ' || char == '\t') {
      final start = i;
      while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
        i++;
      }
      spans.add(TextSpan(text: line.substring(start, i), style: palette.plain));
      continue;
    }
    if ('{}[],:'.contains(char)) {
      spans.add(TextSpan(text: char, style: palette.punct));
      i++;
      continue;
    }
    if (char == '"') {
      final start = i;
      i++;
      while (i < line.length) {
        if (line[i] == '\\' && i + 1 < line.length) {
          i += 2;
          continue;
        }
        if (line[i] == '"') {
          i++;
          break;
        }
        i++;
      }
      var look = i;
      while (look < line.length && line[look] == ' ') {
        look++;
      }
      final isKey = look < line.length && line[look] == ':';
      spans.add(
        TextSpan(
          text: line.substring(start, i),
          style: isKey ? palette.key : palette.string,
        ),
      );
      continue;
    }
    final word = RegExp(r'^(?:true|false|null)').matchAsPrefix(line, i);
    if (word != null) {
      spans.add(TextSpan(text: word.group(0), style: palette.keyword));
      i = word.end;
      continue;
    }
    final number = RegExp(r'^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?')
        .matchAsPrefix(line, i);
    if (number != null) {
      spans.add(TextSpan(text: number.group(0), style: palette.number));
      i = number.end;
      continue;
    }
    spans.add(TextSpan(text: char, style: palette.plain));
    i++;
  }
  return spans;
}
