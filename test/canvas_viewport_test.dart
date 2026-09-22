import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/cables/cable_painter.dart';
import 'package:skapie/paint/paint.dart';
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

  testWidgets('drag LLM kit moves frame and body together', (tester) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final frame = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'frame',
    );
    final body = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'body',
    );
    final frameX = frame.x;
    final bodyX = body.x;
    final offset = bodyX - frameX;
    final selection = SelectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScope(
          tokens: PaintTokens.dark(),
          child: Scaffold(
            body: CanvasViewport(
              store: store,
              selection: selection,
              kitApi: kitApi,
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.dragFrom(center, const Offset(50, 0));
    await tester.pump();

    final movedFrame = store.document.objectById(frame.id)!;
    final movedBody = store.document.objectById(body.id)!;
    expect(movedFrame.x, closeTo(frameX + 50, 0.001));
    expect(movedBody.x, closeTo(bodyX + 50, 0.001));
    expect(movedBody.x - movedFrame.x, closeTo(offset, 0.001));
    expect(movedFrame.y, closeTo(frame.y, 0.001));
    expect(movedBody.y, closeTo(body.y, 0.001));
  });

  testWidgets('drag tools.list_kits moves frame and grant together', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate('tools.list_kits', origin: Offset.zero);
    final frame = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'frame',
    );
    final grant = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'grant',
    );
    final offset = grant.x - frame.x;
    final selection = SelectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScope(
          tokens: PaintTokens.dark(),
          child: Scaffold(
            body: CanvasViewport(
              store: store,
              selection: selection,
              kitApi: kitApi,
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.dragFrom(center, const Offset(50, 0));
    await tester.pump();

    final movedFrame = store.document.objectById(frame.id)!;
    final movedGrant = store.document.objectById(grant.id)!;
    expect(movedFrame.x, closeTo(frame.x + 50, 0.001));
    expect(movedGrant.x, closeTo(grant.x + 50, 0.001));
    expect(movedGrant.x - movedFrame.x, closeTo(offset, 0.001));
  });

  testWidgets('Delete on LLM body removes the whole compound', (tester) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final body = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'body',
    );
    final selection = SelectionController()..select(body.id);
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScope(
          tokens: PaintTokens.dark(),
          child: Scaffold(
            body: CanvasViewport(
              store: store,
              selection: selection,
              kitApi: kitApi,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CanvasViewport));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == harnessLlmKitId,
      ),
      isEmpty,
    );
    expect(selection.selectedId, isNull);
  });

  testWidgets('Delete on tools.list_kits grant removes the whole compound', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate('tools.list_kits', origin: Offset.zero);
    final grant = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'grant',
    );
    final selection = SelectionController()..select(grant.id);
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScope(
          tokens: PaintTokens.dark(),
          child: Scaffold(
            body: CanvasViewport(
              store: store,
              selection: selection,
              kitApi: kitApi,
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == 'tools.list_kits',
      ),
      isEmpty,
    );
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

  testWidgets('double-click text enters inline edit and commits via KitApi', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 't1',
          type: 'text',
          x: -40,
          y: -20,
          width: 80,
          height: 40,
          props: {'content': 'old', 'fontSize': 18, 'color': '#1B1B1B'},
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
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump();

    expect(selection.selectedId, 't1');
    expect(find.byKey(const Key('inline-text-edit')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('inline-text-edit')), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(store.document.objects.single.props['content'], 'hello');
    expect(find.byKey(const Key('inline-text-edit')), findsNothing);
  });

  testWidgets('double-click a text kit edits its text in place', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(boardTextKitId, origin: const Offset(-140, -75));
    final selection = SelectionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(
            store: store,
            kitApi: kitApi,
            selection: selection,
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump();

    expect(find.byKey(const Key('inline-text-edit')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('inline-text-edit')),
      'hello there',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      store.document.objects
          .firstWhere((object) => object.type == 'text')
          .props['content'],
      'hello there',
    );
  });

  testWidgets('hovering a cable shows scissors and a click cuts it', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-220, -20),
    );
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(160, -40),
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, kitApi: kitApi),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final viewport = find.byType(CanvasViewport);
    final size = tester.getSize(viewport);
    final cable = sceneCables(store.document).single;
    final from = worldToScreen(cable.from, size, state.camera);
    final to = worldToScreen(cable.to, size, state.camera);
    final metric = cableCurve(
      from,
      to,
      state.camera.zoom,
    ).computeMetrics().first;
    final mid = metric.getTangentForOffset(metric.length / 2)!.position;
    final global = tester.getTopLeft(viewport) + mid;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: global);
    await gesture.moveTo(global);
    await tester.pump();

    expect(find.byKey(const Key('cable-cut')), findsOneWidget);

    await gesture.down(global);
    await gesture.up();
    await tester.pump();

    expect(
      kitHasLink(
        store.document.objectById(text.first)!,
        to: llm.last,
        port: llmInputPort,
      ),
      isFalse,
    );
    expect(sceneCables(store.document), isEmpty);
  });
}
