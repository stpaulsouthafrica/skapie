import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
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
    expect(find.byKey(const Key('llm-kit-input')), findsOneWidget);
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
}
