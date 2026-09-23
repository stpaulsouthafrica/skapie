import 'package:flutter/material.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';

/// Full-screen editor for a text kit. Saving goes through [KitApi].
Future<void> showTextKitEditor({
  required BuildContext context,
  required KitApi kitApi,
  required String bodyId,
  required String title,
  required String content,
}) {
  final tokens = PaintScope.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close text',
    barrierColor: const Color(0xE60C0C0E),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _TextKitEditor(
        tokens: tokens,
        title: title,
        initial: content,
        onSave: (value) {
          if (value == content) {
            return;
          }
          kitApi.updateProps(bodyId, {'content': value});
        },
      );
    },
  );
}

class _TextKitEditor extends StatefulWidget {
  const _TextKitEditor({
    required this.tokens,
    required this.title,
    required this.initial,
    required this.onSave,
  });

  final PaintTokens tokens;
  final String title;
  final String initial;
  final ValueChanged<String> onSave;

  @override
  State<_TextKitEditor> createState() => _TextKitEditorState();
}

class _TextKitEditorState extends State<_TextKitEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  var _saved = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_saved) {
      return;
    }
    _saved = true;
    widget.onSave(_text.text);
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
        key: const Key('text-kit-editor'),
        color: tokens.canvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: tokens.ink),
                      ),
                    ),
                    IconButton(
                      key: const Key('text-kit-editor-close'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: tokens.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tokens.hairline),
                    ),
                    child: TextField(
                      key: const Key('text-kit-editor-field'),
                      controller: _text,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        color: tokens.ink,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(20),
                      ),
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
}
