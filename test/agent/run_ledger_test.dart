import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/world/kits.dart';

import 'agent_controller_test.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  test(
    'a reader run records events in order without later action kinds',
    () async {
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      sinkLlm(kitApi, ids.last);

      await controller.sendUser('hello', targetBodyId: ids.last);

      final run = controller.latestRunFor(ids.last)!;
      expect(run.schemaVersion, runRecordSchemaVersion);
      expect(run.events.map((event) => event.kind).toList(), [
        RunEventKind.runRequested,
        RunEventKind.graphValidated,
        RunEventKind.modelRequestStarted,
        RunEventKind.modelRequestFinished,
        RunEventKind.runCompleted,
      ]);
      expect(run.events.first.payload['offeredTools'], isNull);
      expect(
        run.events
            .firstWhere(
              (event) => event.kind == RunEventKind.modelRequestStarted,
            )
            .payload['offeredTools'],
        isEmpty,
      );
      expect(run.status, RunStatus.completed);
      _expectIncreasing(run);
      expect(
        RunEventKind.values.map((kind) => kind.name),
        isNot(anyElement(contains('proposal'))),
      );
      expect(
        RunEventKind.values.map((kind) => kind.name),
        isNot(anyElement(contains('approval'))),
      );
      expect(
        RunEventKind.values.map((kind) => kind.name),
        isNot(anyElement(contains('command'))),
      );
      expect(
        kitApi.store.document.toJson().toString(),
        isNot(contains('runRequested')),
      );
    },
  );

  test(
    'an interrupted run ends interrupted with increasing sequence and time',
    () async {
      final model = _HoldModel();
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(model: model, kitApi: kitApi),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      final tool = kitApi.instantiate(
        'tools.list_kits',
        origin: const Offset(400, 0),
      );
      attachToolKit(
        kitApi: kitApi,
        toolObjectId: tool.first,
        llmBodyId: llm.last,
      );
      sinkLlm(kitApi, llm.last);

      final pending = controller.sendUser('kits', targetBodyId: llm.last);
      await model.started.future;
      controller.interruptRun();
      expect(controller.runningBodyId, isNull);
      model.release.complete();
      await pending;

      final run = controller.latestRunFor(llm.last)!;
      expect(run.status, RunStatus.interrupted);
      expect(run.events.last.kind, RunEventKind.runInterrupted);
      expect(
        run.events.map((event) => event.kind),
        isNot(contains(RunEventKind.toolCallStarted)),
      );
      expect(
        kitApi.store.document.objectById(llm.last)!.props['reply'],
        isNot('late'),
      );
      expect(
        run.events.map((event) => event.kind),
        isNot(contains(RunEventKind.runCompleted)),
      );
      expect(
        run.events.map((event) => event.kind),
        contains(RunEventKind.runRequested),
      );
      expect(
        run.events.map((event) => event.kind),
        contains(RunEventKind.graphValidated),
      );
      expect(
        run.events.map((event) => event.kind),
        contains(RunEventKind.modelRequestStarted),
      );
      final offered =
          run.events
                  .firstWhere(
                    (event) => event.kind == RunEventKind.modelRequestStarted,
                  )
                  .payload['offeredTools']
              as List;
      expect(offered, contains('list_kits'));
      _expectIncreasing(run);
    },
  );

  test('a tool loop records each model call around the tool events', () async {
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(
        model: ScriptedAgentModel([
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(id: 'c1', name: 'list_kits', argumentsJson: '{}'),
            ],
          ),
          const AgentModelReply(content: 'done'),
        ]),
        kitApi: kitApi,
      ),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final tool = kitApi.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 0),
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );
    sinkLlm(kitApi, llm.last);

    await controller.sendUser('kits', targetBodyId: llm.last);

    expect(
      controller.latestRunFor(llm.last)!.events.map((event) => event.kind),
      [
        RunEventKind.runRequested,
        RunEventKind.graphValidated,
        RunEventKind.modelRequestStarted,
        RunEventKind.modelRequestFinished,
        RunEventKind.toolCallStarted,
        RunEventKind.toolCallFinished,
        RunEventKind.modelRequestStarted,
        RunEventKind.modelRequestFinished,
        RunEventKind.runCompleted,
      ],
    );
  });

  test('a failed model call ends as failed', () async {
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(
        presetId: 'opencode-go',
        useFake: false,
      ),
    );
    final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    sinkLlm(kitApi, ids.last);

    await expectLater(
      controller.sendUser('hello', targetBodyId: ids.last),
      throwsA(isA<StateError>()),
    );

    final run = controller.latestRunFor(ids.last)!;
    expect(run.status, RunStatus.failed);
    expect(run.events.last.kind, RunEventKind.runFailed);
    expect(
      run.events.map((event) => event.kind),
      contains(RunEventKind.modelRequestStarted),
    );
    expect(
      run.events.map((event) => event.kind),
      contains(RunEventKind.modelRequestFinished),
    );
    expect(
      run.events.map((event) => event.kind),
      isNot(contains(RunEventKind.runCompleted)),
    );
  });

  test(
    'the ledger file sits beside the board and stays out of scene.json',
    () async {
      final dir = await Directory.systemTemp.createTemp('skapie-runs');
      final scene = File('${dir.path}/board.json');
      await scene.writeAsString('{"objects":[]}\n');
      final store = SceneStore(persistence: SceneFilePersistence(scene));
      final api = createAppKitApi(store: store);
      final file = RunLedgerFile.besideScene(store.sceneFilePath)!;
      final controller = AgentController(
        kitApi: api,
        session: AgentSession(model: FakeAgentModel(), kitApi: api),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
        ledgerFile: file,
      );
      final ids = api.instantiate(harnessLlmKitId, origin: Offset.zero);
      sinkLlm(api, ids.last);
      await controller.sendUser('hello', targetBodyId: ids.last);
      await controller.flushLedger();

      expect(file.file.path, endsWith('board.json.runs.json'));
      expect(await scene.readAsString(), isNot(contains('runRequested')));
      final loaded = RunLedger();
      await file.loadInto(loaded);
      expect(loaded.runs.single.events, isNotEmpty);
      expect(loaded.runs.single.status, RunStatus.completed);
      await dir.delete(recursive: true);
    },
  );

  test('token usage is copied only when the response supplies it', () {
    expect(
      tokenUsageFromResponse(
        '{"usage":{"prompt_tokens":3,"completion_tokens":4,"total_tokens":7,"cost":9}}',
      ),
      {'prompt_tokens': 3, 'completion_tokens': 4, 'total_tokens': 7},
    );
    expect(tokenUsageFromResponse('not json'), isNull);
    expect(tokenUsageFromResponse('{"usage":{}}'), isNull);
  });

  test('a large tool result is marked truncated and kept in the record', () {
    final ledger = RunLedger();
    final run = ledger.begin(bodyId: 'llm');
    final huge = 'z' * (runPayloadTextLimit + 40);
    ledger.append(run.id, RunEventKind.toolCallFinished, {
      'name': 'list_kits',
      'result': huge,
    });
    final event = run.events.single;
    expect(event.payload['truncated'], isTrue);
    expect((event.payload['result'] as String).length, runPayloadTextLimit);
    expect(runEventEvidenceLine(event), contains('Truncated'));
    expect(ledger.inspectText(run, event), huge);
    expect(presentRunInspect('{"ok":true}'), '{\n  "ok": true\n}');
    expect(runEvidenceMayDrop('approval'), isFalse);
    expect(runEvidenceMayDrop('revert'), isFalse);
  });

  test('reopening an unfinished run marks it interrupted', () async {
    final dir = await Directory.systemTemp.createTemp('skapie-open-run');
    final scene = File('${dir.path}/board.json');
    await scene.writeAsString('{"objects":[]}\n');
    final file = RunLedgerFile.besideScene(scene.path)!;
    final open = RunLedger();
    final run = open.begin(bodyId: 'llm');
    open.append(run.id, RunEventKind.runRequested, {'bodyId': 'llm'});
    open.append(run.id, RunEventKind.modelRequestStarted, {'offeredTools': []});
    await file.write(open);

    final loaded = RunLedger();
    await file.loadInto(loaded);
    expect(loaded.runs.single.status, RunStatus.interrupted);
    expect(loaded.runs.single.events.last.kind, RunEventKind.runInterrupted);
    expect(
      loaded.runs.single.events.map((event) => event.kind),
      isNot(contains(RunEventKind.runCompleted)),
    );
    await dir.delete(recursive: true);
  });

  test('a large history warns and does not drop events', () {
    final ledger = RunLedger(historyWarnBytes: 80);
    final run = ledger.begin(bodyId: 'llm');
    ledger.append(run.id, RunEventKind.runRequested, {'bodyId': 'llm'});
    final before = run.events.length;
    expect(ledger.historyWarning, isTrue);
    expect(run.events, hasLength(before));
    expect(ledger.runs, hasLength(1));
  });
}

void _expectIncreasing(RunRecord run) {
  for (var i = 0; i < run.events.length; i++) {
    expect(run.events[i].sequence, i + 1);
    expect(run.events[i].schemaVersion, runRecordSchemaVersion);
    if (i > 0) {
      expect(run.events[i].at.isAfter(run.events[i - 1].at), isTrue);
    }
  }
}

class _HoldModel implements AgentModel {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await release.future;
    return const AgentModelReply(
      content: 'late',
      toolCalls: [
        AgentToolCall(id: 'c1', name: 'list_kits', argumentsJson: '{}'),
      ],
    );
  }
}
