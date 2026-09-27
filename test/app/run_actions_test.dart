import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/run_checkpoint.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('Replay looks without running; Resume and Rerun are separate', (
    tester,
  ) async {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final input = api.instantiate(boardTextKitId, origin: const Offset(400, 0));
    api.updateProps(input.last, {'content': 'carry on'});
    connectTextToLlm(
      kitApi: api,
      textObjectId: input.first,
      llmBodyId: llm.last,
    );
    final ledger = RunLedger();
    final run = ledger.begin(bodyId: llm.last);
    ledger.append(run.id, RunEventKind.runRequested, {'bodyId': llm.last});
    ledger.append(run.id, RunEventKind.runPaused, {
      'reason': 'Pause requested',
    });
    final checkpoints = RunCheckpointStore();
    await checkpoints.save(
      RunCheckpoint(
        runId: run.id,
        bodyId: llm.last,
        phase: 'paused',
        boundary: RunBoundary.modelResult,
        modelTurns: 1,
        toolCalls: 0,
        outputChars: 0,
        graphRevision: 'g',
        at: DateTime.now(),
      ),
    );
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(model: const FakeAgentModel(), kitApi: api),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      ledger: ledger,
      checkpointStore: checkpoints,
    );
    final selection = SelectionController()..select(llm.last);
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

    final tile = find.byKey(ValueKey('run-evidence-${llm.last}'));
    await tester.ensureVisible(tile);
    await tester.tap(find.byKey(const Key('run-evidence-name')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('run-actions')), findsOneWidget);
    final runsBefore = controller.ledger.runs.length;

    await tester.tap(find.byKey(const Key('run-action-replay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('run-replay-fullscreen')), findsOneWidget);
    expect(controller.ledger.runs.length, runsBefore);
    await tester.tap(find.byKey(const Key('run-replay-close')));
    await tester.pumpAndSettle();

    final resume = find.byKey(const Key('run-action-resume'));
    await tester.ensureVisible(resume);
    expect(tester.widget<TextButton>(resume).onPressed, isNotNull);
    expect(find.byKey(const Key('run-action-rerun')), findsOneWidget);
  });
}
