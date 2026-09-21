import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('chat strip Echo with Fake model does not resize canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);
    await tester.pumpWidget(
      SkapieApp(store: store, kitApi: kitApi, agentSession: session),
    );

    final before = tester.getSize(find.byType(CanvasViewport));
    expect(find.byKey(const Key('agent-chat-input')), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(tester.getSize(find.byType(CanvasViewport)), before);

    await tester.enterText(find.byKey(const Key('agent-chat-input')), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('hello'), findsNothing);
    expect(store.document.objects, isNotEmpty);
    final body = store.document.objects.firstWhere(
      (object) => object.props['skapieRole'] == 'body',
    );
    expect(body.props['skapieKit'], harnessLlmKitId);
    expect(body.props['content'], contains('Echo: hello'));
    expect(tester.getSize(find.byType(CanvasViewport)), before);
    expect(session.messages, hasLength(1));
  });

  testWidgets('chat strip is about one third of the window width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(SkapieApp(store: SceneStore()));
    final bar = tester.getSize(find.byKey(const Key('agent-chat-input')));
    expect(bar.width, closeTo(300, 40));
  });

  testWidgets('settings Use Fake swaps session and does not resize canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      SkapieApp(store: store, kitApi: kitApi, agentController: controller),
    );

    final before = tester.getSize(find.byType(CanvasViewport));

    await tester.enterText(
      find.byKey(const Key('agent-chat-input')),
      '/settings',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.getSize(find.byType(CanvasViewport)), before);

    final sessionBefore = controller.session;
    await tester.tap(find.byKey(const Key('agent-settings-fake')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.session, isNot(same(sessionBefore)));
    expect(controller.runtime.useFake, isTrue);
    expect(store.document.objects, isEmpty);
    expect(tester.getSize(find.byType(CanvasViewport)), before);
  });

  testWidgets('tapping the chat field attaches text input', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(SkapieApp(store: SceneStore()));
    await tester.tap(find.byKey(const Key('agent-chat-input')));
    await tester.pump();

    expect(tester.testTextInput.isRegistered, isTrue);
  });
}
