import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('home screen shows the canvas and no chat bar', (tester) async {
    await tester.pumpWidget(SkapieApp(store: SceneStore()));

    expect(find.byType(CanvasViewport), findsOneWidget);
    expect(find.byKey(const Key('agent-chat-input')), findsNothing);
    expect(find.text('Skapie'), findsNothing);
    expect(find.text('Space to add'), findsOneWidget);
  });

  Future<void> openAddMenu(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  testWidgets('Add menu places box, text, and button kits', (tester) async {
    final store = SceneStore();
    await tester.pumpWidget(SkapieApp(store: store));

    Future<void> add(String label) async {
      await openAddMenu(tester);
      await tester.tap(find.text(label).last);
      await tester.pump();
    }

    await openAddMenu(tester);
    expect(find.text('Debug rect'), findsNothing);
    expect(find.text('Demo kit: note card'), findsNothing);
    expect(find.text('System prompt'), findsNothing);
    await tester.tap(find.text('Box').last);
    await tester.pump();
    await add('Text');
    await add('Button');

    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == boardBoxKitId,
      ),
      isNotEmpty,
    );
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == boardTextKitId,
      ),
      isNotEmpty,
    );
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == boardButtonKitId,
      ),
      isNotEmpty,
    );
  });

  testWidgets('header shows a short scene label, not the absolute path', (
    tester,
  ) async {
    const absolute =
        '/Users/me/Library/Containers/com.skapie.skapie/Data/Library/Application Support/com.skapie.skapie/skapie/scene.json';
    final store = SceneStore(persistence: SceneFilePersistence(File(absolute)));
    await tester.pumpWidget(SkapieApp(store: store));
    expect(find.text('Scene: App Support'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(find.text('Scene: App Support'), findsOneWidget);
    expect(find.textContaining(absolute), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == absolute,
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy path'), findsOneWidget);
  });

  testWidgets('selecting does not change CanvasViewport size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 'box1',
          type: 'box',
          x: -40,
          y: -20,
          width: 80,
          height: 40,
        ),
      ),
    );
    await tester.pumpWidget(SkapieApp(store: store));

    final before = tester.getSize(find.byType(CanvasViewport));
    await tester.tapAt(tester.getCenter(find.byType(CanvasViewport)));
    await tester.pump();

    expect(tester.getSize(find.byType(CanvasViewport)), before);
    expect(find.text('Inspector'), findsOneWidget);
  });
}
