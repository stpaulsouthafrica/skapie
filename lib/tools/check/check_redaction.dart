/// Redact common credential forms before check evidence reaches the board
/// ledger or the UI. Very long lines are withheld as a whole because a secret
/// could straddle arbitrary native read boundaries.
String redactCheckText(String raw) {
  var text = raw;
  text = text.replaceAllMapped(
    RegExp(
      r'\b(authorization\s*:\s*bearer|bearer)\s+[A-Za-z0-9._~+/=-]+',
      caseSensitive: false,
    ),
    (match) => '${match[1]} [REDACTED]',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'''\b([A-Za-z0-9_]*(?:api[_-]?key|token|password|secret|credential)[A-Za-z0-9_]*)\s*[:=]\s*["']?[^\s"'&,;]+''',
      caseSensitive: false,
    ),
    (match) => '${match[1]}=[REDACTED]',
  );
  text = text.replaceAll(
    RegExp(
      r'\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{10,}|AKIA[A-Z0-9]{16})\b',
    ),
    '[REDACTED]',
  );
  text = text.replaceAll(
    RegExp(r'\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'),
    '[REDACTED]',
  );
  return text;
}

/// A native read can split a credential. Release only complete, redacted lines.
/// A no-newline tail is released at process completion. This retains at most
/// one bounded line per stream in raw memory and never persists it.
class CheckLineRedactor {
  static const maxLineLength = 4096;
  final Map<String, String> _pending = {};
  final Set<String> _discarding = {};

  List<String> add(String key, String chunk) {
    final lines = <String>[];
    var pending = _pending[key] ?? '';
    for (final unit in chunk.runes) {
      if (unit == 10) {
        if (_discarding.remove(key)) {
          lines.add('[output line redacted: too long]\n');
        } else {
          lines.add('${redactCheckText(pending)}\n');
        }
        pending = '';
      } else if (!_discarding.contains(key)) {
        pending += String.fromCharCode(unit);
        if (pending.length > maxLineLength) {
          pending = '';
          _discarding.add(key);
        }
      }
    }
    _pending[key] = pending;
    return lines;
  }

  List<(String, String)> finish() {
    final tails = <(String, String)>[];
    for (final key in {..._pending.keys, ..._discarding}) {
      if (_discarding.contains(key)) {
        tails.add((key, '[output line redacted: too long]'));
      } else if ((_pending[key] ?? '').isNotEmpty) {
        tails.add((key, redactCheckText(_pending[key]!)));
      }
    }
    _pending.clear();
    _discarding.clear();
    return tails;
  }
}
