import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('viewport fills and shows zoom hud at 100%', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CanvasViewport(store: SceneStore())),
      ),
    );

    expect(find.byType(CanvasViewport), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('mouse wheel zooms toward the pointer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CanvasViewport(store: SceneStore())),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -240)),
    );
    await tester.pump();

    expect(find.text('200%'), findsOneWidget);
  });

  testWidgets('click object selects it; empty click clears', (tester) async {
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
    final selection = SelectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, selection: selection),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.tapAt(center);
    await tester.pump();
    expect(selection.selectedId, 'box1');

    final topLeft = tester.getTopLeft(find.byType(CanvasViewport));
    await tester.tapAt(topLeft + const Offset(8, 8));
    await tester.pump();
    expect(selection.selectedId, isNull);
  });

  testWidgets('drag unlocked object commits one UpdateObjectFrame', (
    tester,
  ) async {
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
    final selection = SelectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, selection: selection),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.dragFrom(center, const Offset(50, 0));
    await tester.pump();

    final object = store.document.objects.single;
    expect(object.x, closeTo(10, 0.001));
    expect(object.y, closeTo(-20, 0.001));
    store.undo();
    expect(store.document.objects.single.x, closeTo(-40, 0.001));
  });

  testWidgets('locked object selects but does not move', (tester) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 'lock1',
          type: 'box',
          x: -40,
          y: -20,
          width: 80,
          height: 40,
          locked: true,
        ),
      ),
    );
    final selection = SelectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, selection: selection),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.dragFrom(center, const Offset(50, 0));
    await tester.pump();

    expect(selection.selectedId, 'lock1');
    expect(store.document.objects.single.x, closeTo(-40, 0.001));
  });

  testWidgets('Delete key removes selected object and clears selection', (
    tester,
  ) async {
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
    final selection = SelectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, selection: selection),
        ),
      ),
    );

    await tester.tap(find.byType(CanvasViewport));
    await tester.pump();
    expect(selection.selectedId, 'box1');

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(store.document.objects, isEmpty);
    expect(selection.selectedId, isNull);
  });

  testWidgets('middle mouse drag pans without selecting or moving', (
    tester,
  ) async {
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
    final selection = SelectionController();
    final key = GlobalKey<CanvasViewportState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(key: key, store: store, selection: selection),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.down(center, buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(
      pointer.move(center + const Offset(40, 0), buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();

    expect(selection.selectedId, isNull);
    expect(store.document.objects.single.x, closeTo(-40, 0.001));
    expect(key.currentState!.camera.offset.dx, isNot(closeTo(0, 0.001)));
  });
}
