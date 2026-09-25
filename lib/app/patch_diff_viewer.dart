import 'package:flutter/material.dart';
import 'package:skapie/paint/paint.dart';

({int added, int removed}) patchDiffCounts(String diff) {
  var added = 0;
  var removed = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) added++;
    if (line.startsWith('-') && !line.startsWith('---')) removed++;
  }
  return (added: added, removed: removed);
}

Future<void> showPatchDiffViewer({
  required BuildContext context,
  required String path,
  required String diff,
  required String proposalId,
  bool observed = false,
}) {
  final tokens = PaintScope.of(context);
  final lines = diff.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  final counts = patchDiffCounts(diff);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      key: const Key('patch-diff-viewer'),
      backgroundColor: tokens.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Row(
                children: [
                  Icon(Icons.difference_outlined, color: tokens.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          observed
                              ? 'Observed repository change · File effect recorded'
                              : 'Proposed change · Nothing has been written',
                          style: TextStyle(color: tokens.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('patch-diff-close'),
                    tooltip: 'Close diff',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: tokens.ink),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _stat('+${counts.added}', tokens.success),
                  _stat('−${counts.removed}', tokens.danger),
                  _stat('1 file', tokens.accent),
                  Text(
                    'Proposal $proposalId',
                    style: TextStyle(color: tokens.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                decoration: BoxDecoration(
                  color: tokens.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  key: const Key('patch-diff-lines'),
                  itemCount: lines.length,
                  itemBuilder: (context, index) =>
                      _line(tokens, index + 1, lines[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _stat(String text, Color color) => DecoratedBox(
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.14),
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: color.withValues(alpha: 0.45)),
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  ),
);

Widget _line(PaintTokens tokens, int number, String line) {
  final added = line.startsWith('+') && !line.startsWith('+++');
  final removed = line.startsWith('-') && !line.startsWith('---');
  final meta =
      line.startsWith('@@') || line.startsWith('+++') || line.startsWith('---');
  final color = added
      ? tokens.success
      : removed
      ? tokens.danger
      : meta
      ? tokens.accent
      : tokens.ink;
  return Container(
    color: added
        ? tokens.success.withValues(alpha: 0.10)
        : removed
        ? tokens.danger.withValues(alpha: 0.10)
        : null,
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            '$number',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: tokens.muted,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SelectableText(
            line,
            style: TextStyle(
              color: color,
              fontSize: 13,
              height: 1.35,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    ),
  );
}
