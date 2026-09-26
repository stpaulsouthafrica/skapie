import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/run_checkpoint.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/app/run_recovery_banner.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene.dart';

AgentController _controller({
  required RunLedger ledger,
  RunCheckpointStore? checkpointStore,
}) {
  final api = createAppKitApi(store: SceneStore());
  return AgentController(
    kitApi: api,
    session: AgentSession(model: const FakeAgentModel(), kitApi: api),
    runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    ledger: ledger,
    checkpointStore: checkpointStore,
  );
}

Widget _wrap(AgentController controller, ValueChanged<String> onInspect) {
  return MaterialApp(
    home: PaintScope(
      tokens: PaintTokens.dark(),
      child: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              RunRecoveryBanner(controller: controller, onInspect: onInspect),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('recovery banner offers Continue, Inspect, then End', (
    tester,
  ) async {
    final ledger = RunLedger();
    final run = ledger.begin(bodyId: 'llm1');
    ledger.append(run.id, RunEventKind.runRequested, {'bodyId': 'llm1'});
    ledger.append(run.id, RunEventKind.runInterrupted, {'reason': 'reopened'});
    final store = RunCheckpointStore();
    await store.save(
      RunCheckpoint(
        runId: run.id,
        bodyId: 'llm1',
        phase: 'modelWait',
        boundary: RunBoundary.modelResult,
        modelTurns: 1,
        toolCalls: 0,
        outputChars: 0,
        graphRevision: 'g',
        at: DateTime.now(),
      ),
    );
    final controller = _controller(ledger: ledger, checkpointStore: store);
    String? inspected;
    await tester.pumpWidget(_wrap(controller, (id) => inspected = id));

    expect(find.byKey(const Key('run-recovery-banner')), findsOneWidget);
    expect(find.textContaining('Run interrupted'), findsOneWidget);
    expect(find.byKey(const Key('run-recovery-continue')), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-recovery-inspect')));
    expect(inspected, 'llm1');

    await tester.tap(find.byKey(const Key('run-recovery-end')));
    await tester.pumpAndSettle();
    expect(controller.pendingRecovery, isEmpty);
    expect(find.byKey(const Key('run-recovery-banner')), findsNothing);
  });

  testWidgets('an uncertain run hides Continue and asks for inspection', (
    tester,
  ) async {
    final ledger = RunLedger();
    final run = ledger.begin(bodyId: 'llm2');
    ledger.append(run.id, RunEventKind.runRequested, {'bodyId': 'llm2'});
    ledger.append(run.id, RunEventKind.toolCallStarted, {'callId': 'c1'});
    ledger.closeIncompleteRuns();
    final controller = _controller(ledger: ledger);

    await tester.pumpWidget(_wrap(controller, (_) {}));
    expect(find.textContaining('effect uncertain'), findsOneWidget);
    expect(find.byKey(const Key('run-recovery-continue')), findsNothing);
    expect(find.byKey(const Key('run-recovery-inspect')), findsOneWidget);
  });

  test('a loaded interrupted run does not start on its own', () async {
    final ledger = RunLedger();
    final run = ledger.begin(bodyId: 'llm3');
    ledger.append(run.id, RunEventKind.runRequested, {'bodyId': 'llm3'});
    ledger.closeIncompleteRuns();
    final controller = _controller(ledger: ledger);
    expect(controller.pendingRecovery, hasLength(1));
    expect(controller.ledger.runs, hasLength(1));
    expect(controller.runningBodyId, isNull);
  });
}
