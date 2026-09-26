import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/canvas_settings_panel.dart';
import 'package:skapie/app/canvas_shortcut_settings.dart';

void main() {
  test('selection drag key defaults to Shift and survives reload', () async {
    final dir = await Directory.systemTemp.createTemp('skapie-shortcuts-');
    addTearDown(() => dir.delete(recursive: true));
    final file = CanvasShortcutSettings.fileIn(dir);
    final settings = await CanvasShortcutSettings.load(file);
    expect(settings.selectionDragKey, SelectionDragKey.shift);

    await settings.setSelectionDragKey(SelectionDragKey.command);
    expect(
      (await CanvasShortcutSettings.load(file)).selectionDragKey,
      SelectionDragKey.command,
    );
    settings.dispose();
  });

  testWidgets('Canvas setting changes the saved selection drag key', (
    tester,
  ) async {
    final settings = CanvasShortcutSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: CanvasSettingsPanel(settings: settings),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Shift'), findsOneWidget);
    await tester.tap(find.byKey(const Key('selection-drag-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Option').last);
    await tester.pumpAndSettle();
    expect(settings.selectionDragKey, SelectionDragKey.option);
    settings.dispose();
  });
}
