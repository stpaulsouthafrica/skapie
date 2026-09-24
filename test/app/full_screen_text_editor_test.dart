import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/full_screen_text_editor.dart';
import 'package:skapie/paint/paint.dart';

void main() {
  test('detects JSON, Dart, and plain text from the content', () {
    expect(detectEditorSyntax('{\n  "ok": true\n}'), EditorSyntax.json);
    expect(detectEditorSyntax('[1, 2, 3]'), EditorSyntax.json);
    expect(
      detectEditorSyntax(
        "import 'package:flutter/material.dart';\n\n"
        'void main() {\n  final x = 1;\n}\n',
      ),
      EditorSyntax.dart,
    );
    expect(detectEditorSyntax('Buy milk\nCall Anna'), EditorSyntax.plain);
  });

  test('highlighted spans cover the text exactly', () {
    final tokens = PaintTokens.dark();
    const json = '{\n  "name": "skapie",\n  "n": 3,\n  "on": null\n}';
    const dart = "// hi\nclass A extends B {\n  final s = 'x';\n}\n";
    for (final (text, syntax) in [
      (json, EditorSyntax.json),
      (dart, EditorSyntax.dart),
      ('plain', EditorSyntax.plain),
    ]) {
      final span = highlightEditorText(text, syntax, tokens, const TextStyle());
      expect(span.toPlainText(), text);
    }
  });

  testWidgets('numbers lines, tracks hover, and keeps the caret line lit', (
    tester,
  ) async {
    await tester.pumpWidget(
      PaintScope(
        tokens: PaintTokens.dark(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFullScreenTextEditor(
                context: context,
                title: 'Tool call finished',
                text: '{\n  "ok": true,\n  "files": []\n}',
                readOnly: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('full-screen-text-editor')), findsOneWidget);
    for (final n in ['1', '2', '3', '4']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('full-screen-text-editor-syntax')),
        matching: find.text('JSON'),
      ),
      findsOneWidget,
    );

    Color gutter(int line) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(ValueKey('full-screen-text-editor-gutter-$line')),
          matching: find.byType(DecoratedBox),
        ),
      );
      return (box.decoration as BoxDecoration).color!;
    }

    final field = find.byKey(const Key('full-screen-text-editor-field'));
    final origin = tester.getTopLeft(field);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: origin + const Offset(40, 4));
    await mouse.moveTo(origin + const Offset(40, 18 + 20.8 * 2 + 4));
    await tester.pumpAndSettle();
    expect(gutter(2), isNot(Colors.transparent));
    expect(gutter(0), Colors.transparent);

    await tester.tapAt(origin + const Offset(40, 18 + 20.8 * 1 + 4));
    await tester.pumpAndSettle();
    expect(gutter(1), isNot(Colors.transparent));
    await mouse.moveTo(origin + const Offset(40, 18 + 20.8 * 3 + 4));
    await tester.pumpAndSettle();
    expect(gutter(1), isNot(Colors.transparent));
    await mouse.removePointer();

    tester
        .widget<TextField>(
          find.byKey(const Key('full-screen-text-editor-field')),
        )
        .controller!
        .selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 8,
    );
    await tester.pump();
    expect(
      find.byKey(const Key('full-screen-text-editor-position')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('full-screen-text-editor-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('full-screen-text-editor')), findsNothing);
  });

  testWidgets('long lines wrap in the editor instead of scrolling sideways', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final long =
        'Make Test File.rtf cleaner: Content is currently 8 lines of '
        'macOS TextEdit boilerplate that is hard to read because it never '
        'breaks across the viewport and keeps scrolling sideways forever.';
    await tester.pumpWidget(
      PaintScope(
        tokens: PaintTokens.dark(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFullScreenTextEditor(
                context: context,
                title: 'Patch Proposal',
                text: long,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final editor = tester.getSize(
      find.byKey(const Key('full-screen-text-editor')),
    );
    final field = tester.getSize(
      find.byKey(const Key('full-screen-text-editor-field')),
    );
    expect(field.width, lessThan(editor.width));
    expect(field.height, greaterThan(18 + 13 * 1.6 * 2 + 28));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
  });
}
