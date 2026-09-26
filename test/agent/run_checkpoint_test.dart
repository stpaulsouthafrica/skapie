import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/run_checkpoint.dart';
import 'package:skapie/agent/run_control.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

class _PendingModel implements AgentModel {
  final started = Completer<void>();
  final release = Completer<AgentModelReply>();

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) {
    started.complete();
    return release.future;
  }
}

class _SpyCheckpointStore extends RunCheckpointStore {
  _SpyCheckpointStore() : super(file: null);

  final saved = <RunCheckpoint>[];
  final removed = <String>[];

  @override
  Future<void> save(RunCheckpoint checkpoint) async {
    saved.add(checkpoint);
  }

  @override
  Future<void> remove(String runId) async {
    removed.add(runId);
  }
}

void main() {
  late KitApi api;
  late String llmBody;
  late _SpyCheckpointStore spy;

  setUp(() {
    api = createAppKitApi(store: SceneStore());
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final input = api.instantiate(boardTextKitId, origin: const Offset(400, 0));
    final output = api.instantiate(
      boardTextKitId,
      origin: const Offset(800, 0),
    );
    api.updateProps(input.last, {'content': 'do the thing'});
    connectTextToLlm(
      kitApi: api,
      textObjectId: input.first,
      llmBodyId: llm.last,
    );
    addKitLink(
      kitApi: api,
      objectId: llm.last,
      to: output.first,
      port: llmTextOutPort,
    );
    llmBody = llm.last;
    spy = _SpyCheckpointStore();
  });

  AgentController buildController({RunCheckpointStore? store}) =>
      AgentController(
        kitApi: api,
        session: AgentSession(model: const FakeAgentModel(), kitApi: api),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
        checkpointStore: store ?? spy,
      );

  test('a checkpoint is small and does not hold the scene', () async {
    final dir = await Directory.systemTemp.createTemp('skapie-checkpoint-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/board.scene.json.checkpoints.json');
    final store = RunCheckpointStore(file: file);
    await store.save(
      RunCheckpoint(
        runId: 'run_1',
        bodyId: 'b1',
        phase: 'paused',
        boundary: RunBoundary.toolResult,
        modelTurns: 2,
        toolCalls: 3,
        outputChars: 40,
        graphRevision: 'abcd1234',
        pendingOperationId: 'c1',
        at: DateTime.utc(2026, 1, 1),
      ),
    );

    final text = await file.readAsString();
    expect(text, contains('run_1'));
    expect(text, contains('toolResult'));
    expect(text, contains('c1'));
    expect(text.length, lessThan(2048));
    expect(text, isNot(contains('objects')));

    final reloaded = RunCheckpointStore(file: file);
    await reloaded.load();
    final checkpoint = reloaded.forRun('run_1')!;
    expect(checkpoint.toolCalls, 3);
    expect(checkpoint.pendingOperationId, 'c1');

    expect(migrateRunCheckpoint({'runId': 'x'})['schemaVersion'], 1);
  });

  test('a run saves checkpoints at model and tool boundaries', () async {
    final controller = buildController();
    final call = const AgentToolCall(
      id: 'c1',
      name: 'list_kits',
      argumentsJson: '{}',
    );
    controller.session = AgentSession(
      model: ScriptedAgentModel([
        AgentModelReply(content: '', toolCalls: [call]),
        const AgentModelReply(content: 'done'),
      ]),
      kitApi: api,
    );
    final tool = api.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 400),
    );
    attachToolKit(kitApi: api, toolObjectId: tool.first, llmBodyId: llmBody);

    await controller.sendUser('kits', targetBodyId: llmBody);
    await controller.flushLedger();

    expect(
      spy.saved.map((checkpoint) => checkpoint.boundary),
      containsAll([
        RunBoundary.graphValidated,
        RunBoundary.modelResult,
        RunBoundary.toolResult,
      ]),
    );
    expect(spy.removed, contains(controller.latestRunFor(llmBody)!.id));
    expect(
      controller
          .latestRunFor(llmBody)!
          .events
          .any((event) => event.kind == RunEventKind.checkpoint),
      isTrue,
    );
  });

  test('a quit after a model boundary shows a resumable run', () async {
    final dir = await Directory.systemTemp.createTemp('skapie-resume-');
    addTearDown(() => dir.delete(recursive: true));
    final ledgerFile = RunLedgerFile(File('${dir.path}/board.runs.json'));
    final checkpoints = RunCheckpointStore(
      file: File('${dir.path}/board.checkpoints.json'),
    );
    final ledger = RunLedger();
    final run = ledger.begin(bodyId: llmBody);
    ledger.append(run.id, RunEventKind.runRequested, {'bodyId': llmBody});
    ledger.append(run.id, RunEventKind.graphValidated, {'ok': true});
    ledger.append(run.id, RunEventKind.modelRequestStarted, {});
    await ledgerFile.write(ledger);
    await checkpoints.save(
      RunCheckpoint(
        runId: run.id,
        bodyId: llmBody,
        phase: 'modelWait',
        boundary: RunBoundary.graphValidated,
        modelTurns: 0,
        toolCalls: 0,
        outputChars: 0,
        graphRevision: 'g',
        at: DateTime.now(),
      ),
    );

    final resumeStore = RunCheckpointStore(
      file: File('${dir.path}/board.checkpoints.json'),
    );
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(model: const FakeAgentModel(), kitApi: api),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      ledgerFile: ledgerFile,
      checkpointStore: resumeStore,
    );
    await controller.loadLedger();

    final notice = controller.pendingRecovery.single;
    expect(notice.runId, run.id);
    expect(notice.uncertain, isFalse);
    expect(notice.resumable, isTrue);

    await controller.resumeRun(llmBody);
    await controller.flushLedger();
    final resumed = controller.latestRunFor(llmBody)!;
    expect(resumed.resumedFrom, run.id);
    expect(
      resumed.events.any((event) => event.kind == RunEventKind.runResumed),
      isTrue,
    );

    await controller.endRun(resumed.id);
    expect(controller.pendingRecovery, isEmpty);

    final reloaded = RunCheckpointStore(
      file: File('${dir.path}/board.checkpoints.json'),
    );
    await reloaded.load();
    expect(reloaded.isDismissed(resumed.id), isTrue);
  });

  test('a resumed session counts carried turns against the limit', () async {
    final session = AgentSession(
      model: ScriptedAgentModel([const AgentModelReply(content: 'done')]),
      kitApi: api,
      limits: const RunLimits(modelTurns: 2),
      startModelTurns: 2,
    );
    await expectLater(
      session.sendUser('go'),
      throwsA(
        isA<RunLimitReached>().having((e) => e.name, 'name', 'model turns'),
      ),
    );
  });

  test('stop propagates to a waiting model', () async {
    final gate = Completer<void>();
    final session = AgentSession(model: _PendingModel(), kitApi: api);
    final pending = session.sendUser('go', cancellation: gate.future);
    gate.complete();
    await expectLater(pending, throwsA(isA<AgentRunInterrupted>()));
  });

  test('an effect with no result reloads as uncertain', () async {
    final dir = await Directory.systemTemp.createTemp('skapie-uncertain-');
    addTearDown(() => dir.delete(recursive: true));
    final ledger = RunLedger();
    final run = ledger.begin(bodyId: llmBody);
    ledger.append(run.id, RunEventKind.runRequested, {'bodyId': llmBody});
    ledger.append(run.id, RunEventKind.toolCallStarted, {'callId': 'c1'});
    ledger.closeIncompleteRuns();
    expect(runRecordEffectUncertain(run), isTrue);
    expect(run.events.last.payload['uncertain'], isTrue);
  });
}
