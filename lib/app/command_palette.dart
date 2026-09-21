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
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<CommandAction> get _filtered =>
      filterCommandActions(widget.actions, _query.text);

  void _run(CommandAction action) => widget.onRun(action);

  void _runFirst() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return;
    }
    _run(filtered.first);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final filtered = _filtered;
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
              onSubmitted: (_) => _runFirst(),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final action in filtered)
                    InkWell(
                      key: Key('command-action-${action.id}'),
                      onTap: () => _run(action),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
