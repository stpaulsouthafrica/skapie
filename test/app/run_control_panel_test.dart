import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/app/run_control_panel.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('Run Control starts only its cabled LLM', (tester) async {
    final api = createAppKitApi(includeDemotedKits: true, store: SceneStore());
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(model: const FakeAgentModel(), kitApi: api),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final control = api.instantiate(
      harnessRunControlKitId,
      origin: const Offset(400, 0),
    );
    final task = api.instantiate(boardTextKitId, origin: const Offset(-400, 0));
    final conversation = api.instantiate(
      harnessConversationKitId,
      origin: const Offset(800, 0),
    );
    api.updateProps(task.last, {'content': 'hello'});

    void cable(
      String from,
      KitPortKind fromKind,
      String to,
      KitPortKind toKind,
    ) {
      final ports = kitPorts(api.store.document);
      connectKitPorts(
        kitApi: api,
        from: ports.singleWhere(
          (port) => port.frameId == from && port.kind == fromKind,
        ),
        to: ports.singleWhere(
          (port) => port.frameId == to && port.kind == toKind,
        ),
      );
    }

    cable(
      control.first,
      KitPortKind.runControlOut,
      llm.first,
      KitPortKind.runControlIn,
    );
    cable(task.first, KitPortKind.textOut, llm.first, KitPortKind.llmInput);
    cable(
      llm.first,
      KitPortKind.llmConversation,
      conversation.first,
      KitPortKind.conversationIn,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RunControlPanel(
              frame: api.store.document.objectById(control.first)!,
              kitApi: api,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Model turns'), findsOneWidget);
    expect(find.text('Controls cabled LLM'), findsNothing);
    final first = tester.getRect(
      find.byKey(const ValueKey('run-control-modelTurns-8')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('run-control-toolCalls-16')),
    );
    expect(second.top - first.bottom, greaterThan(20));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(first.center);
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.textContaining('Set to 0 to disable this limit.'),
      findsOneWidget,
    );
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('run-control-modelTurns-8')),
      '0',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      api.store.document.objectById(control.first)?.props['modelTurns'],
      0,
    );
    await tester.tap(find.byKey(const ValueKey('run-control-rule-off')));
    await tester.pumpAndSettle();
    expect(find.text('Allow one more turn'), findsOneWidget);
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('run-control-start')));
    await tester.pumpAndSettle();

    expect(controller.latestRunFor(llm.last)?.status, RunStatus.completed);
    expect(
      api.store.document.objectById(llm.last)?.props['reply'],
      'Echo: hello',
    );
  });
}
