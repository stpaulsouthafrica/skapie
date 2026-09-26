import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum SelectionDragKey { shift, control, command, option }

class CanvasShortcutSettings extends ChangeNotifier {
  CanvasShortcutSettings({
    this.file,
    this.selectionDragKey = SelectionDragKey.shift,
  });

  final File? file;
  SelectionDragKey selectionDragKey;

  static File fileIn(Directory appSupportDirectory) =>
      File('${appSupportDirectory.path}/skapie/canvas_shortcuts.json');

  static Future<CanvasShortcutSettings> load(File file) async {
    if (!await file.exists()) return CanvasShortcutSettings(file: file);
    try {
      final json = jsonDecode(await file.readAsString());
      final saved = json is Map ? json['selectionDragKey'] : null;
      final key = SelectionDragKey.values.where((key) => key.name == saved);
      return CanvasShortcutSettings(
        file: file,
        selectionDragKey: key.isEmpty ? SelectionDragKey.shift : key.first,
      );
    } on Object {
      return CanvasShortcutSettings(file: file);
    }
  }

  Future<void> setSelectionDragKey(SelectionDragKey key) async {
    if (key == selectionDragKey) return;
    if (file != null) {
      await file!.parent.create(recursive: true);
      await file!.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert({'selectionDragKey': key.name}),
      );
    }
    selectionDragKey = key;
    notifyListeners();
  }
}
