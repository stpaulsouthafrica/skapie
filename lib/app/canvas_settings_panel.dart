import 'package:flutter/material.dart';
import 'package:skapie/app/canvas_shortcut_settings.dart';

class CanvasSettingsPanel extends StatelessWidget {
  const CanvasSettingsPanel({super.key, required this.settings});

  final CanvasShortcutSettings settings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Canvas', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<SelectionDragKey>(
          key: const Key('selection-drag-key'),
          initialValue: settings.selectionDragKey,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Multi-select drag key',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: SelectionDragKey.shift,
              child: Text('Shift'),
            ),
            DropdownMenuItem(
              value: SelectionDragKey.control,
              child: Text('Control'),
            ),
            DropdownMenuItem(
              value: SelectionDragKey.command,
              child: Text('Command'),
            ),
            DropdownMenuItem(
              value: SelectionDragKey.option,
              child: Text('Option'),
            ),
          ],
          onChanged: (key) async {
            if (key == null) return;
            try {
              await settings.setSelectionDragKey(key);
            } on Object {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not save canvas shortcut'),
                  ),
                );
              }
            }
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Hold this key and drag to select cards and cables.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
