import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/app/llm_kit_input.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    SceneStore? store,
    KitApi? kitApi,
    AgentController? controller,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scene = store ?? SceneStore();
    final api = kitApi ?? createAppKitApi(store: scene);
    await tester.pumpWidget(
      SkapieApp(
        store: scene,
        kitApi: api,
        agentController:
            controller ??
            AgentController(
              kitApi: api,
              session: AgentSession(model: FakeAgentModel(), kitApi: api),
              runtime: const ResolvedAgentRuntime(
                presetId: 'fake',
                useFake: true,
              ),
            ),
      ),
    );
    await tester.pump();
  }

  testWidgets('home has a full-bleed canvas and no persistent chat bar', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byType(CanvasViewport), findsOneWidget);
    expect(find.byKey(const Key('agent-chat-input')), findsNothing);
    expect(find.text('Space to add'), findsOneWidget);
  });

  testWidgets('Space and F3 open the command palette; Esc closes it', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsOneWidget);
    expect(find.byKey(const Key('command-palette-search')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsOneWidget);
  });

  testWidgets('space in the inspector types a space', (tester) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    kitApi.instantiate(boardTextKitId, origin: const Offset(-140, -75));
    await pumpHome(tester, store: store, kitApi: kitApi);

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.tapAt(center);
    await tester.pump();
    final field = find.byKey(const Key('inspector-content'));
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'say hello');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      'say hello',
    );
  });

  testWidgets('hover then Enter runs the hovered palette action', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    await pumpHome(tester, store: store, kitApi: kitApi);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsOneWidget);

    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('command-action-add-text'))),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == boardTextKitId,
      ),
      isNotEmpty,
    );
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == harnessLlmKitId,
      ),
      isEmpty,
    );
  });

  testWidgets('arrow then Enter runs the highlighted palette action', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    await pumpHome(tester, store: store, kitApi: kitApi);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == boardTextKitId,
      ),
      isNotEmpty,
    );
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == harnessLlmKitId,
      ),
      isEmpty,
    );
  });

  testWidgets('Add LLM from the palette instantiates harness.llm via KitApi', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    await pumpHome(tester, store: store, kitApi: kitApi);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(find.text('Add LLM'));
    await tester.pump();

    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == harnessLlmKitId,
      ),
      hasLength(2),
    );
    expect(find.byType(LlmKitInput), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InspectorPanel),
        matching: find.byKey(const Key('llm-kit-input')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(InspectorPanel),
        matching: find.byKey(const Key('llm-kit-model')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(InspectorPanel),
        matching: find.byKey(const Key('kit-swatches')),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'selected LLM kit Enter runs vanilla onto that kit, not a global agent',
    (tester) async {
      final store = SceneStore();
      final kitApi = createAppKitApi(store: store);
      await pumpHome(tester, store: store, kitApi: kitApi);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.tap(find.text('Add LLM'));
      await tester.pump();

      await tester.enterText(find.byKey(const Key('llm-kit-input')), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final body = store.document.objects.firstWhere(
        (object) =>
            object.props[skapieKitProp] == harnessLlmKitId &&
            object.props[skapieRoleProp] == 'body',
      );
      expect(body.props['prompt'], 'hello');
      expect(body.props['content'], contains('Echo: hello'));
      expect(body.props['content'], contains('Input'));
      expect(body.props['content'], contains('Output'));
      expect(find.byKey(const Key('agent-chat-input')), findsNothing);
    },
  );

  testWidgets('palette Settings opens the settings sheet', (tester) async {
    await pumpHome(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('command-palette-search')),
      'set',
    );
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(find.text('Agent settings'), findsOneWidget);
  });

  testWidgets('palette Tool: list_kits instantiates tools.list_kits', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    await pumpHome(tester, store: store, kitApi: kitApi);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('command-palette-search')),
      'list_kits',
    );
    await tester.pump();
    await tester.tap(find.text('Tool: list_kits'));
    await tester.pump();

    expect(find.byKey(const Key('command-palette')), findsNothing);
    expect(
      store.document.objects.where(
        (object) => object.props[skapieKitProp] == 'tools.list_kits',
      ),
      isNotEmpty,
    );
  });

  testWidgets('palette Attach to LLM links the tool and writes Tools chrome', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    await pumpHome(tester, store: store, kitApi: kitApi);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(find.text('Add LLM'));
    await tester.pump();

    final canvas = tester.getTopLeft(find.byType(CanvasViewport));
    await tester.tapAt(canvas + const Offset(8, 8));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('command-palette-search')),
      'list_kits',
    );
    await tester.pump();
    await tester.tap(find.text('Tool: list_kits'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('command-palette-search')),
      'attach',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('command-action-attach-to-llm')));
    await tester.pump();

    final llmBody = store.document.objects.firstWhere(
      (object) => object.props[skapieRoleProp] == 'body',
    );
    final grant = store.document.objects.firstWhere(
      (object) => object.props['toolName'] == 'list_kits',
    );
    expect(
      kitHasLink(grant, to: llmBody.id, port: llmToolsPort),
      isTrue,
    );
    expect(llmBody.props['content'], contains('Tools: list_kits'));
  });

  testWidgets('settings Use Fake swaps session and does not resize canvas', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await pumpHome(
      tester,
      store: store,
      kitApi: kitApi,
      controller: controller,
    );
    final before = tester.getSize(find.byType(CanvasViewport));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    final sessionBefore = controller.session;
    await tester.tap(find.byKey(const Key('agent-settings-fake')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.session, isNot(same(sessionBefore)));
    expect(controller.runtime.useFake, isTrue);
    expect(store.document.objects, isEmpty);
    expect(tester.getSize(find.byType(CanvasViewport)), before);
  });

  testWidgets('LLM kit shows mark, model picker, and Needs input', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    await pumpHome(tester, store: store, kitApi: kitApi);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(find.text('Add LLM'));
    await tester.pump();

    expect(find.byKey(const Key('llm-kit-mark')), findsWidgets);
    expect(find.byKey(const Key('llm-kit-chrome')), findsOneWidget);
    expect(find.byKey(const Key('llm-kit-model')), findsOneWidget);
    expect(find.text('Needs input'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('llm-kit-model')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('llm-kit-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GLM-5.3-Flash').last);
    await tester.pump();

    final body = store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == harnessLlmKitId &&
          object.props[skapieRoleProp] == 'body',
    );
    expect(body.props['model'], 'glm-5.3-flash');
    expect(body.props['provider'], 'opencode-go');
    expect(body.props['surface'], 'completions');
  });
}
