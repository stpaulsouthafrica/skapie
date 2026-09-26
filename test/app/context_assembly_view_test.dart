import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('Context Assembly preview shows sources and a missing cable', (
    tester,
  ) async {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final task = api.instantiate(boardTextKitId, origin: const Offset(400, 0));
    api.updateProps(task.last, {'content': 'Add a text kit'});
    connectTextToLlm(
      kitApi: api,
      textObjectId: task.first,
      llmBodyId: llm.last,
    );
    api.instantiate(harnessConversationKitId, origin: const Offset(800, 0));
    final selection = SelectionController()..select(llm.last);
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(model: const FakeAgentModel(), kitApi: api),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(
            store: store,
            selection: selection,
            kitApi: api,
            controller: controller,
          ),
        ),
      ),
    );

    final toggle = find.byKey(const Key('context-assembly-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('context-assembly')), findsOneWidget);
    expect(find.byKey(const Key('context-layer-task')), findsOneWidget);
    expect(find.text('Add a text kit'), findsOneWidget);
    expect(find.text('Not cabled to Conversation'), findsOneWidget);
  });

  testWidgets('two unused sources do not collide in the exclusion list', (
    tester,
  ) async {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    api.instantiate(boardTextKitId, origin: const Offset(400, 0));
    api.instantiate(boardTextKitId, origin: const Offset(400, 200));
    final selection = SelectionController()..select(llm.last);
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(model: const FakeAgentModel(), kitApi: api),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(
            store: store,
            selection: selection,
            kitApi: api,
            controller: controller,
          ),
        ),
      ),
    );

    final toggle = find.byKey(const Key('context-assembly-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('context-assembly')), findsOneWidget);
    expect(find.text('Not cabled to Input or Context'), findsNWidgets(2));
  });
}
