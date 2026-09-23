import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/canvas/cable_layer.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/paint/cables/cable_painter.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('keyboard connects a port and Escape clears the ring', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    kitApi.instantiate(boardTextKitId, origin: const Offset(-320, 280));
    kitApi.instantiate(
      harnessConversationKitId,
      origin: const Offset(320, 280),
    );
    await tester.pumpWidget(
      SkapieApp(
        store: store,
        kitApi: kitApi,
        agentController: AgentController(
          kitApi: kitApi,
          session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
          runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.byKey(const Key('focused-port')), findsNothing);
    expect(find.byKey(const Key('command-palette')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(find.byKey(const Key('focused-port')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.byKey(const Key('focused-port')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('command-palette-search')),
              matching: find.byType(TextField),
            ),
          )
          .decoration!
          .hintText,
      'Connect Input',
    );
    expect(find.text('Text · Out'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('command-palette')),
        matching: find.textContaining('Conversation'),
      ),
      findsNothing,
    );

    // Desktop Enter reaches onSubmitted through the text input engine.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(find.byKey(const Key('connection-inspector')), findsNothing);
    expect(find.byKey(const Key('focused-port')), findsOneWidget);
    expect(sceneCables(store.document), hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('focused-port')), findsNothing);
    expect(sceneCables(store.document), hasLength(1));
  });

  testWidgets('Connect mode lists the live cable and cuts it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-320, 280),
    );
    final ports = kitPorts(store.document);
    connectKitPorts(
      kitApi: kitApi,
      from: ports.firstWhere(
        (port) =>
            port.frameId == text.first && port.kind == KitPortKind.textOut,
      ),
      to: ports.firstWhere(
        (port) =>
            port.frameId == llm.first && port.kind == KitPortKind.llmInput,
      ),
    );
    await tester.pumpWidget(
      SkapieApp(
        store: store,
        kitApi: kitApi,
        agentController: AgentController(
          kitApi: kitApi,
          session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
          runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Cut · Text · Out'), findsOneWidget);
    expect(find.text('Text · Out'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(sceneCables(store.document), isEmpty);
    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(find.byKey(const Key('focused-port')), findsOneWidget);
    final retraction = tester
        .widget<CableLayer>(find.byType(CableLayer).first)
        .retractions
        .single;
    expect(retraction.cut, 0.5);
  });

  testWidgets('Escape closes Connect mode and leaves the port ring', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    await tester.pumpWidget(
      SkapieApp(
        store: store,
        kitApi: kitApi,
        agentController: AgentController(
          kitApi: kitApi,
          session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
          runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(find.byKey(const Key('focused-port')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('inspector Cut cable retracts from the middle', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-320, 40),
    );
    final ports = kitPorts(store.document);
    connectKitPorts(
      kitApi: kitApi,
      from: ports.firstWhere(
        (port) =>
            port.frameId == text.first && port.kind == KitPortKind.textOut,
      ),
      to: ports.firstWhere(
        (port) =>
            port.frameId == llm.first && port.kind == KitPortKind.llmInput,
      ),
    );
    await tester.pumpWidget(
      SkapieApp(
        store: store,
        kitApi: kitApi,
        agentController: AgentController(
          kitApi: kitApi,
          session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
          runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
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
    expect(find.byKey(const Key('connection-inspector')), findsOneWidget);

    await tester.tap(find.text('Cut cable'));
    await tester.pump();

    expect(sceneCables(store.document), isEmpty);
    expect(find.byKey(const Key('connection-inspector')), findsNothing);
    final retraction = tester
        .widget<CableLayer>(find.byType(CableLayer).first)
        .retractions
        .single;
    expect(retraction.cut, 0.5);
  });
}
