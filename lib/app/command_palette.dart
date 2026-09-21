import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/paint/paint.dart';

class CommandAction {
  const CommandAction({required this.id, required this.label});

  final String id;
  final String label;
}

const List<CommandAction> defaultCommandActions = [
  CommandAction(id: 'add-llm', label: 'Add LLM'),
  CommandAction(id: 'add-system-prompt', label: 'Add System Prompt'),
  CommandAction(id: 'add-tools', label: 'Add Tools'),
  CommandAction(id: 'add-box', label: 'Add Box'),
  CommandAction(id: 'add-text', label: 'Add Text'),
  CommandAction(id: 'add-button', label: 'Add Button'),
  CommandAction(id: 'add-debug-rect', label: 'Add Debug rect'),
  CommandAction(id: 'add-note-card', label: 'Add Note card'),
  CommandAction(id: 'settings', label: 'Settings'),
];

List<CommandAction> filterCommandActions(
  List<CommandAction> actions,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return actions;
  }
  return [
    for (final action in actions)
      if (_matches(action, q)) action,
  ];
}

int moveCommandHighlight({
  required int index,
  required int delta,
  required int length,
}) {
  if (length <= 0) {
    return 0;
  }
  final next = index + delta;
  if (next < 0) {
    return 0;
  }
  if (next >= length) {
    return length - 1;
  }
  return next;
}

bool _matches(CommandAction action, String query) {
  final hay = '${action.label} ${action.id}'.toLowerCase();
  if (hay.contains(query)) {
    return true;
  }
  final compactHay = hay.replaceAll(RegExp(r'[\s\-]+'), '');
  final compactQuery = query.replaceAll(RegExp(r'[\s\-]+'), '');
  return compactHay.contains(compactQuery);
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.actions,
    required this.onClose,
    required this.onRun,
  });

  final List<CommandAction> actions;
  final VoidCallback onClose;
  final ValueChanged<CommandAction> onRun;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  late final FocusNode _searchFocus;
  final _itemKeys = <String, GlobalKey>{};
  var _highlight = 0;

  @override
  void initState() {
    super.initState();
    _searchFocus = FocusNode(onKeyEvent: _onSearchKey);
    _query.addListener(_onQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _query.removeListener(_onQuery);
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<CommandAction> get _filtered =>
      filterCommandActions(widget.actions, _query.text);

  void _onQuery() {
    setState(() => _highlight = 0);
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final control = HardwareKeyboard.instance.isControlPressed;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        (control && event.logicalKey == LogicalKeyboardKey.keyN)) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        (control && event.logicalKey == LogicalKeyboardKey.keyP)) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  GlobalKey _keyFor(String id) {
    return _itemKeys.putIfAbsent(id, GlobalKey.new);
  }

  void _moveHighlight(int delta) {
    final filtered = _filtered;
    setState(() {
      _highlight = moveCommandHighlight(
        index: _highlight,
        delta: delta,
        length: filtered.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || filtered.isEmpty) {
        return;
      }
      final id = _filtered[_highlight].id;
      final ctx = _keyFor(id).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
      }
    });
  }

  void _run(CommandAction action) => widget.onRun(action);

  void _runHighlighted() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return;
    }
    final index = moveCommandHighlight(
      index: _highlight,
      delta: 0,
      length: filtered.length,
    );
    _run(filtered[index]);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final filtered = _filtered;
    final highlight = moveCommandHighlight(
      index: _highlight,
      delta: 0,
      length: filtered.length,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: PaintPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaintTextField(
              key: const Key('command-palette-search'),
              controller: _query,
              focusNode: _searchFocus,
              autofocus: true,
              hint: 'Search',
              onSubmitted: (_) => _runHighlighted(),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final action = filtered[index];
                  final selected = index == highlight;
                  return MouseRegion(
                    onEnter: (_) {
                      if (_highlight == index) {
                        return;
                      }
                      setState(() => _highlight = index);
                    },
                    child: DecoratedBox(
                      key: _keyFor(action.id),
                      decoration: BoxDecoration(
                        color: selected
                            ? tokens.accent.withValues(alpha: 0.22)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: InkWell(
                        key: Key('command-action-${action.id}'),
                        onTap: () => _run(action),
                        onHover: (inside) {
                          if (!inside || _highlight == index) {
                            return;
                          }
                          setState(() => _highlight = index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Text(
                            action.label,
                            style: TextStyle(color: tokens.ink, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
