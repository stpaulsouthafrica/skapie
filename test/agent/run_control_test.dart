import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/run_control.dart';
import 'package:skapie/agent/run_error.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

void main() {
  late KitApi api;

  setUp(() => api = createAppKitApi(store: SceneStore()));

  test('terminal states do not allow more work in the same run', () {
    expect(runPhaseCanMove(RunPhase.ready, RunPhase.validating), true);
    expect(runPhaseCanMove(RunPhase.modelWait, RunPhase.toolWait), true);
    expect(runPhaseCanMove(RunPhase.cancelling, RunPhase.paused), true);
    expect(runPhaseCanMove(RunPhase.completed, RunPhase.modelWait), false);
    expect(runPhaseCanMove(RunPhase.failed, RunPhase.toolWait), false);
  });

  void cable(
    String fromFrame,
    KitPortKind fromKind,
    String toFrame,
    KitPortKind toKind,
  ) {
    final ports = kitPorts(api.store.document);
    connectKitPorts(
      kitApi: api,
      from: ports.singleWhere(
        (port) => port.frameId == fromFrame && port.kind == fromKind,
      ),
      to: ports.singleWhere(
        (port) => port.frameId == toFrame && port.kind == toKind,
      ),
    );
  }

  test(
    'Run Control only changes a cabled LLM and a failed check adds one turn',
    () {
      final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
      final control = api.instantiate(
        harnessRunControlKitId,
        origin: const Offset(400, 0),
      );
      final check = api.instantiate(
        codingCheckResultKitId,
        origin: const Offset(800, 0),
      );
      api.updateProps(control.first, {
        'modelTurns': 2,
        'failedCheckRule': 'oneMoreTurn',
      });
      api.updateProps(check.last, {'checkOutcome': 'nonzero_exit'});

      expect(runLimitsFor(api.store.document, llm.last).modelTurns, 8);
      cable(
        control.first,
        KitPortKind.runControlOut,
        llm.first,
        KitPortKind.runControlIn,
      );
      expect(runLimitsFor(api.store.document, llm.last).effectiveModelTurns, 2);
      cable(
        check.first,
        KitPortKind.checkResultOut,
        control.first,
        KitPortKind.runCheckFeedback,
      );
      expect(runLimitsFor(api.store.document, llm.last).effectiveModelTurns, 3);
      api.updateProps(control.first, {'failedCheckRule': 'off'});
      expect(runLimitsFor(api.store.document, llm.last).effectiveModelTurns, 2);
    },
  );

  test('model turn and tool call limits stop the session by name', () async {
    const call = AgentToolCall(
      id: 'c1',
      name: 'list_kits',
      argumentsJson: '{}',
    );
    final limitedTurns = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(content: '', toolCalls: [call]),
      ]),
      kitApi: api,
      limits: const RunLimits(modelTurns: 1),
    );
    await expectLater(
      limitedTurns.sendUser('kits'),
      throwsA(
        isA<RunLimitReached>().having((e) => e.name, 'name', 'model turns'),
      ),
    );

    final limitedCalls = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(content: '', toolCalls: [call, call]),
      ]),
      kitApi: api,
      limits: const RunLimits(toolCalls: 1),
    );
    await expectLater(
      limitedCalls.sendUser('kits'),
      throwsA(
        isA<RunLimitReached>().having((e) => e.name, 'name', 'tool calls'),
      ),
    );
  });

  test(
    'failed-check rule permits exactly one additional model request',
    () async {
      const toolReply = AgentModelReply(
        content: '',
        toolCalls: [
          AgentToolCall(id: 'c1', name: 'list_kits', argumentsJson: '{}'),
        ],
      );
      final model = ScriptedAgentModel([
        toolReply,
        toolReply,
        const AgentModelReply(content: 'done'),
      ]);
      const limits = RunLimits(modelTurns: 2, extraTurnAfterFailedCheck: true);
      final session = AgentSession(
        model: model,
        kitApi: api,
        limits: limits,
        maxToolIterations: limits.effectiveModelTurns,
      );
      await session.sendUser('repair');
      expect(model.completeCount, 3);
      expect(session.messages.last.content, 'done');

      final noFeedback = AgentSession(
        model: ScriptedAgentModel([toolReply, toolReply]),
        kitApi: api,
        limits: const RunLimits(modelTurns: 2),
        maxToolIterations: 2,
      );
      await expectLater(
        noFeedback.sendUser('repair'),
        throwsA(isA<RunLimitReached>()),
      );
    },
  );

  test(
    'unconnected tool denial is recorded before the next model call',
    () async {
      final model = ScriptedAgentModel([
        const AgentModelReply(
          content: 'draft',
          toolCalls: [
            AgentToolCall(
              id: 'bad',
              name: 'remove_object',
              argumentsJson: '{}',
            ),
          ],
        ),
        const AgentModelReply(content: 'done'),
      ]);
      final controller = AgentController(
        kitApi: api,
        session: AgentSession(model: model, kitApi: api),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
      final attached = api.instantiate(
        'tools.list_kits',
        origin: const Offset(400, 0),
      );
      final conversation = api.instantiate(
        harnessConversationKitId,
        origin: const Offset(800, 0),
      );
      attachToolKit(
        kitApi: api,
        toolObjectId: attached.first,
        llmBodyId: llm.last,
      );
      cable(
        llm.first,
        KitPortKind.llmConversation,
        conversation.first,
        KitPortKind.conversationIn,
      );
      await controller.sendUser('try', targetBodyId: llm.last);
      final run = controller.latestRunFor(llm.last)!;
      final denial = run.events.singleWhere(
        (event) => event.kind == RunEventKind.toolCallFinished,
      );
      expect(denial.payload['denied'], true);
      final nextModel = run.events
          .where((event) => event.kind == RunEventKind.modelRequestStarted)
          .last;
      expect(denial.sequence, lessThan(nextModel.sequence));
      expect(controller.toolPulse, 0);
      expect(api.store.document.objectById(llm.last)!.props['reply'], 'done');
    },
  );

  test('lost repository grant denies the call at dispatch time', () async {
    final grant = _ToggleRepositoryPermission();
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(model: _RevokingModel(grant), kitApi: api),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      repositoryPermission: grant,
    );
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final repository = api.instantiate(
      codingRepositoryKitId,
      origin: const Offset(0, 400),
    );
    final tool = api.instantiate(
      'tools.repo_list_files',
      origin: const Offset(400, 400),
    );
    final conversation = api.instantiate(
      harnessConversationKitId,
      origin: const Offset(800, 0),
    );
    api.updateProps(repository.first, {repositoryPathProp: '/example'});
    cable(
      repository.first,
      KitPortKind.repositoryOut,
      tool.first,
      KitPortKind.toolRepository,
    );
    cable(tool.first, KitPortKind.toolOut, llm.first, KitPortKind.llmTools);
    cable(
      llm.first,
      KitPortKind.llmConversation,
      conversation.first,
      KitPortKind.conversationIn,
    );
    await expectLater(
      controller.sendUser('list files', targetBodyId: llm.last),
      throwsA(isA<StateError>()),
    );
    final run = controller.latestRunFor(llm.last)!;
    expect(
      run.events
          .firstWhere((event) => event.kind == RunEventKind.toolCallFinished)
          .payload['denied'],
      true,
    );
    expect(controller.toolPulse, 0);
    expect(run.status, RunStatus.failed);
  });

  test('elapsed time and output volume stop a session', () async {
    final hold = Completer<AgentModelReply>();
    final timed = AgentSession(
      model: _PendingModel(hold.future),
      kitApi: api,
      limits: const RunLimits(elapsed: Duration(milliseconds: 10)),
    );
    await expectLater(
      timed.sendUser('wait'),
      throwsA(
        isA<RunLimitReached>().having((e) => e.name, 'name', 'elapsed time'),
      ),
    );
    hold.complete(const AgentModelReply(content: 'late'));

    final large = AgentSession(
      model: const FakeAgentModel(),
      kitApi: api,
      limits: const RunLimits(outputChars: 3),
    );
    await expectLater(
      large.sendUser('long'),
      throwsA(
        isA<RunLimitReached>().having((e) => e.name, 'name', 'output volume'),
      ),
    );
  });

  test(
    'pause settles after the model reply without publishing draft text',
    () async {
      final hold = Completer<AgentModelReply>();
      final controller = AgentController(
        kitApi: api,
        session: AgentSession(model: _PendingModel(hold.future), kitApi: api),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
      final tool = api.instantiate(
        'tools.list_kits',
        origin: const Offset(400, 0),
      );
      final conversation = api.instantiate(
        harnessConversationKitId,
        origin: const Offset(800, 0),
      );
      attachToolKit(kitApi: api, toolObjectId: tool.first, llmBodyId: llm.last);
      cable(
        llm.first,
        KitPortKind.llmConversation,
        conversation.first,
        KitPortKind.conversationIn,
      );
      final pending = controller.sendUser('wait', targetBodyId: llm.last);
      await Future<void>.delayed(Duration.zero);
      controller.pauseRun();
      expect(controller.runPhase, RunPhase.cancelling);
      hold.complete(const AgentModelReply(content: 'draft'));
      await pending;
      expect(controller.latestRunFor(llm.last)?.status, RunStatus.paused);
      expect(api.store.document.objectById(llm.last)?.props['reply'], '');
      expect(controller.activeToolFrameId, isNull);
    },
  );

  test('provider errors have actionable categories', () {
    expect(
      classifyRunError(AgentHttpException('bad', statusCode: 401)),
      RunErrorKind.authentication,
    );
    expect(
      classifyRunError(AgentHttpException('slow', statusCode: 429)),
      RunErrorKind.rateLimit,
    );
    expect(classifyRunError(TimeoutException('slow')), RunErrorKind.timeout);
    expect(
      classifyRunError(http.ClientException('offline')),
      RunErrorKind.transport,
    );
    expect(
      classifyRunError(
        AgentHttpException('invalid tool schema', statusCode: 400),
      ),
      RunErrorKind.invalidToolSchema,
    );
    expect(
      classifyRunError(
        AgentHttpException('context length exceeded', statusCode: 400),
      ),
      RunErrorKind.contextLimit,
    );
    expect(
      classifyRunError(AgentHttpException('refusal', statusCode: 400)),
      RunErrorKind.modelRefusal,
    );
  });

  test('fake and HTTP providers use the same visible run states', () async {
    Future<List<String>> statesFor(
      AgentModel model,
      ResolvedAgentRuntime runtime,
    ) async {
      final kitApi = createAppKitApi(store: SceneStore());
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(model: model, kitApi: kitApi),
        runtime: runtime,
      );
      final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      final tool = kitApi.instantiate(
        'tools.list_kits',
        origin: const Offset(400, 0),
      );
      final conversation = kitApi.instantiate(
        harnessConversationKitId,
        origin: const Offset(800, 0),
      );
      attachToolKit(
        kitApi: kitApi,
        toolObjectId: tool.first,
        llmBodyId: llm.last,
      );
      final ports = kitPorts(kitApi.store.document);
      connectKitPorts(
        kitApi: kitApi,
        from: ports.singleWhere(
          (port) =>
              port.frameId == llm.first &&
              port.kind == KitPortKind.llmConversation,
        ),
        to: ports.singleWhere(
          (port) =>
              port.frameId == conversation.first &&
              port.kind == KitPortKind.conversationIn,
        ),
      );
      await controller.sendUser('hello', targetBodyId: llm.last);
      final run = controller.latestRunFor(llm.last)!;
      expect(run.status, RunStatus.completed);
      return [
        for (final event in run.events)
          if (event.kind == RunEventKind.stateChanged)
            event.payload['state'] as String,
      ];
    }

    final fake = await statesFor(
      const FakeAgentModel(),
      const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    final real = await statesFor(
      OpenAiCompatibleAgentModel(
        baseUrl: 'https://example.test/v1',
        apiKey: 'test-key',
        model: 'test-model',
        httpClient: MockClient(
          (_) async => http.Response(
            '{"choices":[{"message":{"content":"done"}}]}',
            200,
          ),
        ),
      ),
      const ResolvedAgentRuntime(
        presetId: 'openai',
        useFake: false,
        model: 'test-model',
      ),
    );
    expect(real, fake);
    expect(
      real,
      containsAllInOrder([
        RunPhase.validating.name,
        RunPhase.assembling.name,
        RunPhase.modelWait.name,
        RunPhase.completed.name,
      ]),
    );
  });
}

class _PendingModel implements AgentModel {
  const _PendingModel(this.reply);
  final Future<AgentModelReply> reply;

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) => reply;
}

class _ToggleRepositoryPermission implements RepositoryPermission {
  bool allowed = true;

  @override
  Future<bool> canRead(String path) async => allowed;

  @override
  Future<String?> chooseDirectory() async => null;
}

class _RevokingModel implements AgentModel {
  _RevokingModel(this.permission);
  final _ToggleRepositoryPermission permission;

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    permission.allowed = false;
    return const AgentModelReply(
      content: '',
      toolCalls: [
        AgentToolCall(id: 'read', name: 'repo_list_files', argumentsJson: '{}'),
      ],
    );
  }
}
