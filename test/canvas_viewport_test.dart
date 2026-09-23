import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/cable_layer.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/cables/cable_hit.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/scene_object_layer.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/cables/cable_painter.dart';
import 'package:skapie/paint/issue_flash_painter.dart';
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

  testWidgets('hovering a tool shows its description', (tester) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate('tools.list_kits', origin: Offset.zero);
    final frame = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'frame',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScope(
          tokens: PaintTokens.dark(),
          child: Scaffold(
            body: CanvasViewport(store: store, kitApi: kitApi),
          ),
        ),
      ),
    );
    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final center = worldToScreen(
      Offset(frame.x + frame.width / 2, frame.y + frame.height / 2),
      tester.getSize(find.byType(CanvasViewport)),
      state.camera,
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await gesture.moveTo(center);
    await tester.pump();
    expect(find.byKey(const Key('tool-hover-description')), findsOneWidget);
    expect(find.text('List registered kits.'), findsOneWidget);
    await gesture.removePointer();
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

  testWidgets('double-click a text kit opens a full-screen editor', (
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

    expect(find.byKey(const Key('text-kit-editor')), findsOneWidget);
    expect(find.byKey(const Key('inline-text-edit')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('text-kit-editor-field')),
      'hello there',
    );
    await tester.tap(find.byKey(const Key('text-kit-editor-close')));
    await tester.pumpAndSettle();

    expect(
      store.document.objects
          .firstWhere((object) => object.type == 'text')
          .props['content'],
      'hello there',
    );
  });

  testWidgets('double-click a conversation kit opens a chat view', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final conversation = kitApi.instantiate(
      harnessConversationKitId,
      origin: const Offset(-140, -75),
    );
    const reply = 'Here is the breakdown:\n\n**Root level:**\n- logo.png';
    appendConversationExchange(
      kitApi: kitApi,
      bodyId: conversation.last,
      userText: 'What is in this folder?',
      assistantText: reply,
    );
    final before = store.document.objectById(conversation.last)!.props;
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

    expect(find.byKey(const Key('conversation-kit-viewer')), findsOneWidget);
    expect(find.byKey(const Key('text-kit-editor')), findsNothing);
    final user = find.byKey(const Key('conversation-turn-user'));
    final assistant = find.byKey(const Key('conversation-turn-assistant'));
    expect(user, findsOneWidget);
    expect(assistant, findsOneWidget);
    final userBubble = tester.getRect(
      find.descendant(of: user, matching: find.byType(DecoratedBox)),
    );
    final assistantBubble = tester.getRect(
      find.descendant(of: assistant, matching: find.byType(DecoratedBox)),
    );
    expect(userBubble.right, greaterThan(assistantBubble.right));
    expect(assistantBubble.left, lessThan(userBubble.left));
    expect(find.textContaining('**Root level:**'), findsOneWidget);

    await tester.tap(find.byKey(const Key('conversation-kit-viewer-close')));
    await tester.pumpAndSettle();
    final after = store.document.objectById(conversation.last)!.props;
    expect(after[turnsProp], before[turnsProp]);
    expect(
      conversationTurnsOf(store.document.objectById(conversation.last)!)
          .map((turn) => turn.role),
      ['user', 'assistant'],
    );
  });

  testWidgets('compatible ports grow as a cable nears and settle after', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-420, -60),
    );
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(40, -100),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, kitApi: kitApi),
        ),
      ),
    );
    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final viewport = find.byType(CanvasViewport);
    final size = tester.getSize(viewport);
    final ports = kitPorts(store.document);
    Offset screen(KitPortKind kind) =>
        tester.getTopLeft(viewport) +
        worldToScreen(
          ports.firstWhere((port) => port.kind == kind).center,
          size,
          state.camera,
        );
    Size mark(KitPortKind kind) =>
        tester.getSize(find.byKey(ValueKey('${kind.name}-${llm.first}')));
    final rest = mark(KitPortKind.llmInput);
    expect(mark(KitPortKind.llmTools), rest);

    final gesture = await tester.startGesture(
      screen(KitPortKind.textOut),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(screen(KitPortKind.llmInput) + const Offset(-30, 0));
    await tester.pump();
    expect(mark(KitPortKind.llmInput).width, greaterThan(rest.width * 1.2));
    expect(
      mark(KitPortKind.llmInput).width,
      greaterThan(mark(KitPortKind.llmContext).width),
    );
    expect(mark(KitPortKind.llmTools), rest);

    await gesture.moveTo(screen(KitPortKind.llmInput));
    await gesture.up();
    await tester.pump();
    expect(kitLinksOf(store.document.objectById(text.first)!), hasLength(1));
    expect(mark(KitPortKind.llmInput).width, greaterThan(rest.width));
    await tester.pumpAndSettle();
    expect(mark(KitPortKind.llmInput), rest);
  });

  testWidgets('a drop that connects nothing retreats to its port', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-420, -60),
    );
    kitApi.instantiate(harnessLlmKitId, origin: const Offset(40, -100));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, kitApi: kitApi),
        ),
      ),
    );
    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final viewport = find.byType(CanvasViewport);
    final size = tester.getSize(viewport);
    final ports = kitPorts(store.document);
    Offset screen(KitPortKind kind) =>
        tester.getTopLeft(viewport) +
        worldToScreen(
          ports.firstWhere((port) => port.kind == kind).center,
          size,
          state.camera,
        );
    List<RetractingCable> retractions() =>
        tester.widget<CableLayer>(find.byType(CableLayer).first).retractions;

    final source = ports
        .firstWhere((port) => port.kind == KitPortKind.textOut)
        .center;
    var count = 0;
    for (final drop in [
      screen(KitPortKind.textOut) + const Offset(120, 160),
      screen(KitPortKind.llmTools),
    ]) {
      final gesture = await tester.startGesture(
        screen(KitPortKind.textOut),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(drop);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      count++;
      expect(retractions(), hasLength(count));
      expect(retractions().last.cut, 1);
      expect(retractions().last.from, source);
    }
    expect(
      retractions().last.to,
      ports.firstWhere((port) => port.kind == KitPortKind.llmTools).center,
    );
    expect(kitLinksOf(store.document.objectById(text.first)!), isEmpty);
  });

  testWidgets('scissors show only on a selected cable, at its middle', (
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
    expect(find.byKey(const Key('cable-cut')), findsNothing);

    await gesture.down(global);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('cable-cut')), findsOneWidget);
    final scissors = tester.getCenter(find.byKey(const Key('cable-cut')));
    expect((scissors - global).distance, lessThan(1.5));
    expect(sceneCables(store.document), hasLength(1));

    await gesture.down(scissors);
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
    store.undo();
    expect(sceneCables(store.document), hasLength(1));
  });

  testWidgets('clicking a cable selects it; Delete cuts; Undo restores', (
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
    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final viewport = find.byType(CanvasViewport);
    final size = tester.getSize(viewport);
    final cable = sceneCables(store.document).single;
    final metric = cableCurve(
      worldToScreen(cable.from, size, state.camera),
      worldToScreen(cable.to, size, state.camera),
      state.camera.zoom,
    ).computeMetrics().first;
    final mid =
        tester.getTopLeft(viewport) +
        metric.getTangentForOffset(metric.length / 2)!.position;

    await tester.tapAt(mid, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(selection.selectedCableId, cable.id);
    expect(sceneCables(store.document), hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(sceneCables(store.document), isEmpty);
    expect(selection.selectedCableId, isNull);

    store.undo();
    await tester.pump();
    expect(sceneCables(store.document).single.id, cable.id);
  });

  testWidgets('[ and ] reach a cable from the keyboard, then Backspace cuts', (
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
    selection.select(text.first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    final cable = sceneCables(store.document).single;
    expect(selection.selectedCableId, cable.id);
    expect(find.byKey(const Key('cable-cut')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(sceneCables(store.document), isEmpty);
    store.undo();
    await tester.pump();
    expect(sceneCables(store.document), hasLength(1));
  });

  testWidgets('the LLM header play button runs the cabled input', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 0),
    );
    kitApi.updateProps(text.last, {'content': 'hello'});
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    final out = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(400, 0),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: out.first,
      port: llmTextOutPort,
    );
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScope(
          tokens: PaintTokens.dark(),
          child: Scaffold(
            body: CanvasViewport(
              store: store,
              kitApi: kitApi,
              agentController: controller,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('llm-kit-run-button'))),
    );
    await tester.pump();
    await tester.pump();

    final body = store.document.objectById(llm.last)!;
    expect(body.props['prompt'], 'hello');
    expect(body.props['reply'], 'Echo: hello');
  });

  testWidgets('the LLM header play button does not run without a sink', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 0),
    );
    kitApi.updateProps(text.last, {'content': 'hello'});
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PaintScope(
          tokens: PaintTokens.dark(),
          child: Scaffold(
            body: CanvasViewport(
              store: store,
              kitApi: kitApi,
              agentController: controller,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('llm-kit-run-button'))),
    );
    await tester.pump();
    await tester.pump();

    final body = store.document.objectById(llm.last)!;
    expect(body.props['prompt'], '');
    expect(body.props['reply'], '');
    expect(
      find.text("Can't run LLM: Needs Output or Conversation"),
      findsOneWidget,
    );
  });

  testWidgets('Run with an empty Input opens the board issues for that LLM', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final reply = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(500, 0),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: reply.first,
      port: llmTextOutPort,
    );
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(
            store: store,
            kitApi: kitApi,
            agentController: controller,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('board-issues-button')), findsOneWidget);
    expect(find.text('1 issue blocks Run'), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('llm-kit-run-button'))),
    );
    await tester.pump();

    expect(find.byKey(const Key('board-run-notice')), findsOneWidget);
    expect(find.text("Can't run LLM: Needs input"), findsOneWidget);
    expect(find.byKey(const Key('board-issues-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-issue-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-issue-row-1')), findsNothing);
    expect(store.document.objectById(llm.last)!.props['prompt'], '');
  });

  testWidgets('the issues panel lists several issues without crashing', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    kitApi.instantiate(harnessLlmKitId, origin: const Offset(500, 0));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, kitApi: kitApi),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('board-issues-button')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('board-issues-panel')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'board-issue-row',
            ),
      ),
      findsNWidgets(4),
    );
  });

  testWidgets('clicking an issue tints it and double-flashes its ports', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    kitApi.instantiate(harnessLlmKitId, origin: const Offset(500, 0));
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
    await tester.tap(find.byKey(const Key('board-issues-button')));
    await tester.pump();
    Color rowColor(int index) => tester
        .widget<Material>(find.byKey(ValueKey('board-issue-row-$index')))
        .color!;
    expect(rowColor(1), Colors.transparent);

    await tester.tap(find.byKey(const ValueKey('board-issue-row-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rowColor(1), isNot(Colors.transparent));
    expect(rowColor(0), Colors.transparent);
    expect(selection.selectedId, llm.first);
    final flash = tester.widget<CustomPaint>(
      find.byKey(const Key('issue-port-flash')),
    );
    expect((flash.painter! as IssueFlashPainter).points, hasLength(2));

    await tester.pump(issueFlashDuration);
    expect(find.byKey(const Key('issue-port-flash')), findsNothing);
    expect(rowColor(1), isNot(Colors.transparent));
  });

  testWidgets('clicking the empty board clears the inspected issue', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    kitApi.instantiate(harnessLlmKitId, origin: const Offset(500, 0));
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
    await tester.tap(find.byKey(const Key('board-issues-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('board-issue-row-0')));
    await tester.pump();

    Color rowColor() => tester
        .widget<Material>(find.byKey(const ValueKey('board-issue-row-0')))
        .color!;
    expect(rowColor(), isNot(Colors.transparent));
    expect(selection.selectedId, isNotNull);

    final board = tester.getBottomLeft(find.byType(CanvasViewport));
    await tester.tapAt(board + const Offset(24, -24));
    await tester.pump();

    expect(selection.selectedId, isNull);
    expect(rowColor(), Colors.transparent);
  });

  testWidgets('a blocked Run traces its first blocker on the board', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(
            store: store,
            kitApi: kitApi,
            agentController: controller,
          ),
        ),
      ),
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('llm-kit-run-button'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester
          .widget<Material>(find.byKey(const ValueKey('board-issue-row-0')))
          .color,
      isNot(Colors.transparent),
    );
    final flash = tester.widget<CustomPaint>(
      find.byKey(const Key('issue-port-flash')),
    );
    expect((flash.painter! as IssueFlashPainter).points, hasLength(1));
    await tester.pump(issueFlashDuration);
  });

  testWidgets('zoomed out, the hidden play spot does not run the LLM', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 0),
    );
    kitApi.updateProps(text.last, {'content': 'hello'});
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    final out = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(400, 0),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: out.first,
      port: llmTextOutPort,
    );
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(
            store: store,
            kitApi: kitApi,
            agentController: controller,
          ),
        ),
      ),
    );
    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final viewport = find.byType(CanvasViewport);
    final center = tester.getCenter(viewport);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 600)),
    );
    await tester.pumpAndSettle();
    expect(state.camera.zoom, lessThan(kitOverviewZoom));
    expect(find.byKey(const Key('llm-kit-run-button')), findsNothing);

    final frame = store.document.objectById(llm.first)!;
    final play =
        tester.getTopLeft(viewport) +
        worldToScreen(
          llmRunButtonCenter(frame),
          tester.getSize(viewport),
          state.camera,
        );
    await tester.tapAt(play, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(store.document.objectById(llm.last)!.props['prompt'], '');
  });

  testWidgets('crossing the overview zoom eases instead of snapping', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, kitApi: kitApi),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 600)),
    );
    await tester.pump();
    await tester.pump(kitOverviewTransition ~/ 2);

    expect(find.byKey(const Key('llm-kit-chrome')), findsOneWidget);
    final overviews = find.byKey(ValueKey('kit-overview-${llm.first}'));
    expect(overviews, findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('llm-kit-chrome')), findsNothing);
    expect(overviews, findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -600)),
    );
    await tester.pump();
    await tester.pump(kitOverviewTransition ~/ 2);
    expect(find.byKey(const Key('llm-kit-chrome')), findsOneWidget);
    expect(overviews, findsOneWidget);
    await tester.pumpAndSettle();
    expect(overviews, findsNothing);
  });

  test('the issue flash pulses twice', () {
    expect(IssueFlashPainter.pulses(0.25), [0.5]);
    expect(IssueFlashPainter.pulses(0.5), [1.0, 0.0]);
    expect(IssueFlashPainter.pulses(0.75), [0.5]);
  });

  testWidgets('Text Out over LLM Tools shows why and does not connect', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-420, -60),
    );
    kitApi.instantiate(harnessLlmKitId, origin: const Offset(40, -100));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, kitApi: kitApi),
        ),
      ),
    );
    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final viewport = find.byType(CanvasViewport);
    final size = tester.getSize(viewport);
    final ports = kitPorts(store.document);
    Offset screen(KitPortKind kind) =>
        tester.getTopLeft(viewport) +
        worldToScreen(
          ports.firstWhere((port) => port.kind == kind).center,
          size,
          state.camera,
        );

    final gesture = await tester.startGesture(
      screen(KitPortKind.textOut),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(screen(KitPortKind.llmTools));
    await tester.pump();
    expect(find.text('Tools takes Tool, not Text'), findsOneWidget);
    await gesture.up();
    await tester.pump();

    expect(kitLinksOf(store.document.objectById(text.first)!), isEmpty);
    expect(
      find.text('Not connected: Tools takes Tool, not Text'),
      findsOneWidget,
    );
  });

  testWidgets('a stale cable after a delete is drawn and can be cut', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-220, -60),
    );
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(200, -40),
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    removeKitSelection(kitApi: kitApi, selectedId: llm.first);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: store, kitApi: kitApi),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 warning'), findsOneWidget);
    final state = tester.state<CanvasViewportState>(
      find.byType(CanvasViewport),
    );
    final viewport = find.byType(CanvasViewport);
    final size = tester.getSize(viewport);
    final stale = validateBoard(store.document).extraCables.single;
    final from = worldToScreen(stale.from, size, state.camera);
    final to = worldToScreen(stale.to, size, state.camera);
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
    expect(find.byKey(const Key('cable-cut')), findsNothing);
    await gesture.down(global);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('cable-cut')), findsOneWidget);
    final scissors = tester.getCenter(find.byKey(const Key('cable-cut')));
    await gesture.down(scissors);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(kitLinksOf(store.document.objectById(text.first)!), isEmpty);
    expect(validateBoard(store.document).issues, isEmpty);
    expect(find.byKey(const Key('board-issues-button')), findsNothing);
  });
}
