import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('text content submit applies UpdateObjectProps; undo restores', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 't1',
          type: 'text',
          x: 0,
          y: 0,
          width: 80,
          height: 40,
          props: {'content': 'old', 'fontSize': 18, 'color': '#1B1B1B'},
        ),
      ),
    );
    final selection = SelectionController()..select('t1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('inspector-content')), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(store.document.objects.single.props['content'], 'hello');
    store.undo();
    expect(store.document.objects.single.props['content'], 'old');
  });

  testWidgets(
    'slow content typing accumulates without select-all wipe',
    (tester) async {
      final store = SceneStore();
      store.apply(
        AddObject(
          const SceneObject(
            id: 't1',
            type: 'text',
            x: 0,
            y: 0,
            width: 80,
            height: 40,
            props: {'content': 'old', 'fontSize': 18, 'color': '#1B1B1B'},
          ),
        ),
      );
      final selection = SelectionController()..select('t1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectorPanel(store: store, selection: selection),
          ),
        ),
      );

      final field = find.byKey(const Key('inspector-content'));
      await tester.tap(field);
      await tester.pump();

      await tester.enterText(field, 'h');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      EditableText editable() {
        return tester.widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
      }

      expect(editable().controller.text, 'h');
      expect(editable().controller.selection.isCollapsed, isTrue);
      expect(editable().controller.selection.baseOffset, 1);

      await tester.enterText(field, 'he');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(field, 'hel');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(editable().controller.text, 'hel');
      expect(editable().controller.selection.isCollapsed, isTrue);
      expect(store.document.objects.single.props['content'], 'hel');
    },
  );

  testWidgets('Delete button removes the object and clears selection', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 'b1',
          type: 'box',
          x: 0,
          y: 0,
          width: 80,
          height: 40,
        ),
      ),
    );
    final selection = SelectionController()..select('b1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(store.document.objects, isEmpty);
    expect(selection.selectedId, isNull);
  });

  testWidgets('Locked switch applies SetObjectLocked; undo restores', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 'b1',
          type: 'box',
          x: 0,
          y: 0,
          width: 80,
          height: 40,
        ),
      ),
    );
    final selection = SelectionController()..select('b1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(store.document.objects.single.locked, isTrue);
    store.undo();
    expect(store.document.objects.single.locked, isFalse);
  });
}
