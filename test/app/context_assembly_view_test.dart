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
  testWidgets('Context Assembly opens full screen without a chevron', (
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

    expect(find.byKey(const Key('context-assembly-toggle')), findsNothing);
    final expand = find.byKey(const Key('context-assembly-expand'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('context-assembly-fullscreen')), findsOneWidget);
    expect(find.textContaining('Task input'), findsWidgets);
    expect(find.textContaining('Add a text kit'), findsWidgets);
    expect(find.textContaining('Not cabled to Conversation'), findsWidgets);
  });

  testWidgets('two unused sources both show in the full screen preview', (
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

    final expand = find.byKey(const Key('context-assembly-expand'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('context-assembly-fullscreen')), findsOneWidget);
    expect(
      find.textContaining('Not cabled to Input or Context'),
      findsWidgets,
    );
  });
}
