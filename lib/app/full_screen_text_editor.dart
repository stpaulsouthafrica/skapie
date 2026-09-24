import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/app/llm_request_highlight.dart';
import 'package:skapie/paint/paint.dart';

/// Language the Full Screen text editor colors the text as.
enum EditorSyntax { plain, json, dart, request }

String editorSyntaxLabel(EditorSyntax syntax) => switch (syntax) {
  EditorSyntax.plain => 'Text',
  EditorSyntax.json => 'JSON',
  EditorSyntax.dart => 'Dart',
  EditorSyntax.request => 'Request',
};

/// Picks JSON or Dart from the text itself. Anything else stays plain.
EditorSyntax detectEditorSyntax(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      jsonDecode(text);
      return EditorSyntax.json;
    } on FormatException {
      if (_jsonKey.hasMatch(text)) {
        return EditorSyntax.json;
      }
    }
  }
  var score = 0;
  for (final hint in _dartHints) {
    if (hint.hasMatch(text)) {
      score++;
    }
  }
  return score >= 2 ? EditorSyntax.dart : EditorSyntax.plain;
}

final _jsonKey = RegExp(r'"[^"\n]*"\s*:');
final _dartHints = [
  RegExp(r"^\s*import\s+'(package|dart):", multiLine: true),
  RegExp(r'\b(void|Future<[^>]*>|Widget|String|int|bool)\s+\w+\s*\('),
  RegExp(r'\b(final|const|var|late)\s+\w+\s*='),
  RegExp(r'\bclass\s+\w+(\s+extends|\s+implements|\s+with|\s*\{)'),
  RegExp(r'@override\b'),
  RegExp(r'=>\s*\S'),
  RegExp(r';\s*$', multiLine: true),
];

/// The one Full Screen text editor. Text kits edit through it; run evidence
/// and the request preview open it read-only.
Future<void> showFullScreenTextEditor({
  required BuildContext context,
  required String title,
  required String text,
  bool readOnly = false,
  ValueChanged<String>? onSave,
  EditorSyntax? syntax,
  String? details,
  Key surfaceKey = const Key('full-screen-text-editor'),
  Key fieldKey = const Key('full-screen-text-editor-field'),
  Key closeKey = const Key('full-screen-text-editor-close'),
}) {
  final tokens = PaintScope.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close $title',
    barrierColor: const Color(0xE60C0C0E),
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return FullScreenTextEditor(
        key: surfaceKey,
        tokens: tokens,
        title: title,
        initial: text,
        readOnly: readOnly,
        onSave: onSave,
        syntax: syntax,
        details: details,
        fieldKey: fieldKey,
        closeKey: closeKey,
      );
    },
  );
}

class FullScreenTextEditor extends StatefulWidget {
  const FullScreenTextEditor({
    super.key,
    required this.tokens,
    required this.title,
    required this.initial,
    this.readOnly = false,
    this.onSave,
    this.syntax,
    this.details,
    this.fieldKey = const Key('full-screen-text-editor-field'),
    this.closeKey = const Key('full-screen-text-editor-close'),
  });

  final PaintTokens tokens;
  final String title;
  final String initial;
  final bool readOnly;
  final ValueChanged<String>? onSave;

  /// Fixed language. Null detects it from the text on every edit.
  final EditorSyntax? syntax;

  /// Facts shown above the text. The payload stays in the editor.
  final String? details;
  final Key fieldKey;
  final Key closeKey;

  @override
  State<FullScreenTextEditor> createState() => _FullScreenTextEditorState();
}

const double _fontSize = 13;
const double _lineHeightFactor = 1.6;
const double _lineHeight = _fontSize * _lineHeightFactor;
const double _padTop = 18;
const double _padBottom = 28;
const double _codeLeft = 16;
const double _codeRight = 32;
const String _font = 'Menlo';
const List<String> _fontFallback = ['SF Mono', 'monospace', 'Courier'];

class _FullScreenTextEditorState extends State<FullScreenTextEditor> {
  late final _SyntaxController _text = _SyntaxController(
    text: widget.initial,
    tokens: widget.tokens,
    fixed: widget.syntax,
  );
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final ScrollController _vertical = ScrollController();
  var _saved = false;
  int? _hoverLine;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _text.dispose();
    _focus.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _save() {
    if (_saved || widget.readOnly) {
      return;
    }
    _saved = true;
    widget.onSave?.call(_text.text);
  }

  int get _lineCount => '\n'.allMatches(_text.text).length + 1;

  int _lineAt(int offset) {
    final clamped = offset.clamp(0, _text.text.length);
    return '\n'.allMatches(_text.text.substring(0, clamped)).length;
  }

  /// Lines the caret or selection covers. Stays lit after a click or edit.
  (int, int)? get _activeLines {
    final selection = _text.selection;
    if (!selection.isValid) {
      return null;
    }
    final a = _lineAt(selection.baseOffset);
    final b = _lineAt(selection.extentOffset);
    return (math.min(a, b), math.max(a, b));
  }

  int get _column {
    final selection = _text.selection;
    if (!selection.isValid) {
      return 1;
    }
    final offset = selection.extentOffset.clamp(0, _text.text.length);
    if (offset == 0) {
      return 1;
    }
    final lineStart = _text.text.lastIndexOf('\n', offset - 1) + 1;
    return offset - lineStart + 1;
  }

  TextStyle get _codeStyle => TextStyle(
    color: widget.tokens.ink,
    fontFamily: _font,
    fontFamilyFallback: _fontFallback,
    fontSize: _fontSize,
    height: _lineHeightFactor,
  );

  List<int> _visualLineCounts(double textWidth) {
    final width = math.max(1.0, textWidth);
    return [
      for (final line in _text.text.split('\n')) _wrappedLineCount(line, width),
    ];
  }

  int _wrappedLineCount(String line, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: line.isEmpty ? ' ' : line, style: _codeStyle),
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontFamily: _font,
        fontFamilyFallback: _fontFallback,
        fontSize: _fontSize,
        height: _lineHeightFactor,
        forceStrutHeight: true,
      ),
    )..layout(maxWidth: maxWidth);
    final count = math.max(1, painter.computeLineMetrics().length);
    painter.dispose();
    return count;
  }

  int? _logicalLineAt(double dy, List<int> visualCounts) {
    var y = dy - _padTop;
    if (y < 0) {
      return null;
    }
    for (var i = 0; i < visualCounts.length; i++) {
      final height = visualCounts[i] * _lineHeight;
      if (y < height) {
        return i;
      }
      y -= height;
    }
    return null;
  }

  void _focusEnd() {
    _focus.requestFocus();
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _save();
        }
      },
      child: Material(
        color: tokens.canvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                if (widget.details != null &&
                    widget.details!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _details(widget.details!),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.panel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.hairline),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _surface(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(String text) {
    final tokens = widget.tokens;
    return DecoratedBox(
      key: const Key('full-screen-text-editor-details'),
      decoration: BoxDecoration(
        color: tokens.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 140),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: SelectableText(
            'Details\n$text',
            style: TextStyle(
              color: tokens.ink,
              fontSize: 12,
              height: 1.4,
              fontFamily: _font,
              fontFamilyFallback: _fontFallback,
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final tokens = widget.tokens;
    final active = _activeLines;
    final position = active == null
        ? '$_lineCount ${_lineCount == 1 ? 'line' : 'lines'}'
        : 'Ln ${_lineAt(_text.selection.extentOffset) + 1}, Col $_column'
              ' · $_lineCount ${_lineCount == 1 ? 'line' : 'lines'}';
    return Row(
      children: [
        Flexible(
          child: Text(
            widget.title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: tokens.ink),
          ),
        ),
        const SizedBox(width: 12),
        _chip(
          editorSyntaxLabel(_text.syntax),
          key: const Key('full-screen-text-editor-syntax'),
          accent: _text.syntax != EditorSyntax.plain,
        ),
        if (widget.readOnly) ...[const SizedBox(width: 6), _chip('Read only')],
        const Spacer(),
        Text(
          position,
          key: const Key('full-screen-text-editor-position'),
          style: TextStyle(
            color: tokens.muted,
            fontSize: 12,
            fontFamily: _font,
            fontFamilyFallback: _fontFallback,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: widget.closeKey,
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close, color: tokens.muted),
        ),
      ],
    );
  }

  Widget _chip(String label, {Key? key, bool accent = false}) {
    final tokens = widget.tokens;
    final color = accent ? tokens.accent : tokens.muted;
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _surface() {
    final lines = _lineCount;
    final active = _activeLines;
    final digits = math.max(2, '$lines'.length);
    final gutterWidth = 20.0 + digits * 8.2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final codeWidth = math.max(0.0, constraints.maxWidth - gutterWidth);
        final visualCounts = _visualLineCounts(
          codeWidth - _codeLeft - _codeRight,
        );
        final visualLines = visualCounts.fold<int>(0, (sum, n) => sum + n);
        final height = math.max(
          constraints.maxHeight,
          _padTop + visualLines * _lineHeight + _padBottom,
        );
        return Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              onHover: (event) {
                final next = _logicalLineAt(
                  event.localPosition.dy,
                  visualCounts,
                );
                if (next != _hoverLine) {
                  setState(() => _hoverLine = next);
                }
              },
              onExit: (_) => setState(() => _hoverLine = null),
              child: SizedBox(
                height: height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _gutter(gutterWidth, visualCounts, active),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _focusEnd,
                        child: SizedBox(
                          width: codeWidth,
                          height: height,
                          child: _field(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gutter(double width, List<int> visualCounts, (int, int)? active) {
    final tokens = widget.tokens;
    return Container(
      width: width,
      padding: const EdgeInsets.only(top: _padTop),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: tokens.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var line = 0; line < visualCounts.length; line++)
            SizedBox(
              key: ValueKey('full-screen-text-editor-gutter-$line'),
              height: _lineHeight * visualCounts[line],
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _gutterTint(tokens, line, active),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(4),
                  ),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    height: _lineHeight,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${line + 1}',
                          style: TextStyle(
                            color: _gutterInk(tokens, line, active),
                            fontFamily: _font,
                            fontFamilyFallback: _fontFallback,
                            fontSize: 11.5,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field() {
    final tokens = widget.tokens;
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: TextSelectionTheme(
        data: TextSelectionThemeData(
          cursorColor: tokens.accent,
          selectionColor: tokens.accent.withValues(alpha: 0.28),
        ),
        child: TextField(
          key: widget.fieldKey,
          controller: _text,
          focusNode: _focus,
          autofocus: !widget.readOnly,
          readOnly: widget.readOnly,
          maxLines: null,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          style: _codeStyle,
          strutStyle: const StrutStyle(
            fontFamily: _font,
            fontFamilyFallback: _fontFallback,
            fontSize: _fontSize,
            height: _lineHeightFactor,
            forceStrutHeight: true,
          ),
          cursorWidth: 2,
          cursorRadius: const Radius.circular(1),
          decoration: const InputDecoration(
            isCollapsed: true,
            filled: false,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(
              _codeLeft,
              _padTop,
              _codeRight,
              _padBottom,
            ),
          ),
        ),
      ),
    );
  }

  Color _gutterTint(PaintTokens tokens, int line, (int, int)? active) {
    if (active != null && line >= active.$1 && line <= active.$2) {
      return tokens.accent.withValues(alpha: 0.16);
    }
    if (line == _hoverLine) {
      return tokens.ink.withValues(alpha: 0.06);
    }
    return Colors.transparent;
  }

  Color _gutterInk(PaintTokens tokens, int line, (int, int)? active) {
    if (active != null && line >= active.$1 && line <= active.$2) {
      return tokens.accent;
    }
    if (line == _hoverLine) {
      return tokens.ink.withValues(alpha: 0.8);
    }
    return tokens.muted.withValues(alpha: 0.55);
  }
}

class _SyntaxController extends TextEditingController {
  _SyntaxController({
    required super.text,
    required this.tokens,
    required this.fixed,
  });

  final PaintTokens tokens;
  final EditorSyntax? fixed;
  String? _detectedFor;
  EditorSyntax _detected = EditorSyntax.plain;

  EditorSyntax get syntax {
    final pinned = fixed;
    if (pinned != null) {
      return pinned;
    }
    if (_detectedFor != text) {
      _detectedFor = text;
      _detected = detectEditorSyntax(text);
    }
    return _detected;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return highlightEditorText(
      text,
      syntax,
      tokens,
      style ?? const TextStyle(),
    );
  }
}

/// Colored spans for [text]. The spans cover the text exactly.
TextSpan highlightEditorText(
  String text,
  EditorSyntax syntax,
  PaintTokens tokens,
  TextStyle base,
) {
  if (syntax == EditorSyntax.request) {
    final span = highlightLlmRequest(text, tokens, fontSize: _fontSize);
    return TextSpan(style: base, children: [span]);
  }
  if (syntax == EditorSyntax.plain) {
    return TextSpan(style: base, text: text);
  }
  final palette = _EditorPalette.of(tokens);
  final pattern = syntax == EditorSyntax.json ? _jsonToken : _dartToken;
  final children = <InlineSpan>[];
  var at = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > at) {
      children.add(TextSpan(text: text.substring(at, match.start)));
    }
    final token = match.group(0)!;
    final color = syntax == EditorSyntax.json
        ? _jsonColor(match, palette)
        : _dartColor(match, palette);
    children.add(
      TextSpan(
        text: token,
        style: color == null
            ? null
            : TextStyle(
                color: color,
                fontStyle: syntax == EditorSyntax.dart && match.group(1) != null
                    ? FontStyle.italic
                    : null,
              ),
      ),
    );
    at = match.end;
  }
  if (at < text.length) {
    children.add(TextSpan(text: text.substring(at)));
  }
  return TextSpan(style: base, children: children);
}

final _jsonToken = RegExp(
  r'("(?:\\.|[^"\\\n])*")(\s*:)?'
  r'|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)'
  r'|\b(true|false|null)\b'
  r'|([{}\[\],:])',
);

Color? _jsonColor(RegExpMatch match, _EditorPalette palette) {
  if (match.group(1) != null) {
    return match.group(2) != null ? palette.key : palette.string;
  }
  if (match.group(3) != null) {
    return palette.number;
  }
  if (match.group(4) != null) {
    return palette.keyword;
  }
  return palette.punct;
}

final _dartToken = RegExp(
  r'(//[^\n]*|/\*[\s\S]*?\*/)'
  r"|('''[\s\S]*?'''|"
  r'"""[\s\S]*?"""'
  r"|'(?:\\.|[^'\\\n])*'|"
  r'"(?:\\.|[^"\\\n])*")'
  r'|(@\w+)'
  r'|\b(\d+(?:\.\d+)?)\b'
  r'|\b([A-Za-z_$][\w$]*)\b',
);

const _dartKeywords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

Color? _dartColor(RegExpMatch match, _EditorPalette palette) {
  if (match.group(1) != null) {
    return palette.comment;
  }
  if (match.group(2) != null) {
    return palette.string;
  }
  if (match.group(3) != null) {
    return palette.number;
  }
  if (match.group(4) != null) {
    return palette.number;
  }
  final word = match.group(5)!;
  if (_dartKeywords.contains(word)) {
    return palette.keyword;
  }
  if (word[0].toUpperCase() == word[0] && word[0] != '_' && word[0] != r'$') {
    return palette.type;
  }
  return null;
}

class _EditorPalette {
  const _EditorPalette({
    required this.key,
    required this.string,
    required this.number,
    required this.keyword,
    required this.punct,
    required this.comment,
    required this.type,
  });

  factory _EditorPalette.of(PaintTokens tokens) {
    final dark = tokens.isDark;
    return _EditorPalette(
      key: tokens.accent,
      string: dark ? const Color(0xFFC8D6A8) : const Color(0xFF3D6B4F),
      number: dark ? const Color(0xFFE0B15A) : const Color(0xFF8A5A12),
      keyword: dark ? const Color(0xFFC9A4D4) : const Color(0xFF6B4A86),
      punct: tokens.muted,
      comment: tokens.muted.withValues(alpha: 0.8),
      type: dark ? const Color(0xFF8EB7E0) : const Color(0xFF2A5F8A),
    );
  }

  final Color key;
  final Color string;
  final Color number;
  final Color keyword;
  final Color punct;
  final Color comment;
  final Color type;
}
