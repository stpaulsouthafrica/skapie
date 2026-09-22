import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_completion.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/providers/vanilla_responses.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  test(
    'Apply Fake rebuilds session and clears turns, keeps system prompt',
    () async {
      final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);
      final controller = AgentController(
        kitApi: kitApi,
        session: session,
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      await controller.session.sendUser('hello');
      expect(controller.session.messages, hasLength(3));

      await controller.applySettings(providerId: 'fake');

      expect(controller.session, isNot(same(session)));
      expect(controller.session.messages, hasLength(1));
      expect(controller.session.messages.single.role, AgentRole.system);
      expect(
        controller.session.messages.single.content,
        defaultAgentSystemPrompt,
      );
      expect(controller.runtime.useFake, isTrue);
      expect(controller.session.model, isA<FakeAgentModel>());
    },
  );

  test('Apply does not mutate the scene', () async {
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await controller.applySettings(
      providerId: 'opencode-go',
      model: 'kimi-k2.6',
      apiKey: 'oc-test',
    );
    expect(kitApi.store.document.objects, isEmpty);
    expect(controller.prefs?.model, 'kimi-k2.6');
    expect(controller.prefs?.apiKey, 'oc-test');
    expect(controller.prefs?.thinkingLevel, isNull);
  });

  test('Apply persists thinkingLevel without a baseUrl', () async {
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await controller.applySettings(
      providerId: 'openrouter',
      model: 'anthropic/claude-sonnet-4',
      apiKey: 'or-test',
      thinkingLevel: 'high',
    );
    expect(controller.prefs?.thinkingLevel, 'high');
    expect(controller.prefs?.apiKey, 'or-test');
    expect(controller.prefs?.toJson().containsKey('baseUrl'), isFalse);
    expect(controller.session.messages, hasLength(1));
  });

  test(
    'Use Fake persists provider fake without requiring a live session',
    () async {
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      await controller.applySettings(
        providerId: 'opencode-go',
        model: 'kimi-k2.6',
        apiKey: 'oc-test',
      );
      await controller.useFake();
      expect(controller.runtime.useFake, isTrue);
      expect(controller.prefs?.providerId, 'fake');
      expect(controller.session.model, isA<FakeAgentModel>());
    },
  );

  test(
    'sendUser Fake echo materializes the LLM kit and skips the tool loop',
    () async {
      final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);
      final controller = AgentController(
        kitApi: kitApi,
        session: session,
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      await controller.sendUser('hello');
      expect(controller.session.messages, hasLength(1));
      expect(kitApi.store.document.objects, isEmpty);

      final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      await controller.sendUser('hello', targetBodyId: ids.last);
      expect(controller.session.messages, hasLength(1));
      final bodies = kitApi.store.document.objects.where(
        (object) => object.props['skapieRole'] == 'body',
      );
      expect(bodies, hasLength(1));
      expect(bodies.single.props['skapieKit'], harnessLlmKitId);
      expect(bodies.single.props['prompt'], 'hello');
      expect(bodies.single.props['reply'], 'Echo: hello');
      expect(bodies.single.props['content'], contains('Echo: hello'));
      expect(
        jsonEncode(kitApi.store.document.toJson()),
        isNot(contains('apiKey')),
      );

      await controller.sendUser('again', targetBodyId: ids.last);
      expect(
        kitApi.store.document.objects.where(
          (object) => object.props['skapieKit'] == harnessLlmKitId,
        ),
        hasLength(2),
      );
      final updated = kitApi.store.document.objects.firstWhere(
        (object) => object.props['skapieRole'] == 'body',
      );
      expect(updated.props['prompt'], 'again');
      expect(updated.props['reply'], contains('again'));
    },
  );

  test(
    'sendUser publishes the kit-scoped model instead of settings model',
    () async {
      final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      kitApi.updateProps(ids.last, {
        'model': 'deepseek-v4-flash',
        'provider': 'opencode-go',
        'surface': 'completions',
      });
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
        runtime: const ResolvedAgentRuntime(
          presetId: 'fake',
          useFake: true,
          model: 'settings-model',
        ),
      );
      await controller.sendUser('hello', targetBodyId: ids.last);
      final body = kitApi.store.document.objectById(ids.last)!;
      expect(body.props['model'], 'deepseek-v4-flash');
      expect(body.props['provider'], 'opencode-go');
      expect(body.props['surface'], 'completions');
      expect(body.props['reply'], 'Echo: hello');
    },
  );

  test(
    'failed vanilla turn writes redacted HTTP body onto the LLM kit',
    () async {
      Map<String, Object?>? sent;
      final client = MockClient((request) async {
        sent = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        return http.Response(
          '{"type":"error","error":{"message":"Internal server error"}}',
          500,
        );
      });
      final vanilla = VanillaCompletionClient(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        apiKey: 'sk-secret-key',
        model: 'muse-spark-1.2-contributor',
        presetId: 'opencode-go',
        httpClient: client,
      );
      final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);
      final controller = AgentController(
        kitApi: kitApi,
        session: session,
        vanilla: vanilla,
        runtime: const ResolvedAgentRuntime(
          presetId: 'opencode-go',
          useFake: false,
          model: 'muse-spark-1.2-contributor',
          apiKey: 'sk-secret-key',
        ),
      );
      kitApi.instantiate(
        harnessSystemPromptKitId,
        origin: const Offset(400, 24),
      );
      kitApi.instantiate(harnessToolsKitId, origin: const Offset(400, 240));
      final llmIds = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      await expectLater(
        controller.sendUser('hello', targetBodyId: llmIds.last),
        throwsA(isA<AgentHttpException>()),
      );
      expect(sent!['messages'], [
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(sent!.containsKey('tools'), isFalse);
      expect(controller.session.messages, hasLength(1));
      final body = kitApi.store.document.objects.firstWhere(
        (object) => object.props['skapieRole'] == 'body',
      );
      expect(body.props['skapieKit'], harnessLlmKitId);
      expect(body.props['error'], contains('500'));
      expect(body.props['content'], contains('Internal server error'));
      expect(body.props['content'], isNot(contains('sk-secret-key')));
      expect(
        controller.lastDiagnostic?.summary,
        isNot(contains('sk-secret-key')),
      );
      expect(controller.lastDiagnostic?.surface, 'completions');
    },
  );

  test(
    'attached list_kits sendUser posts only that tool on the session path',
    () async {
      Map<String, Object?>? sent;
      final client = MockClient((request) async {
        sent = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'listed'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final model = OpenAiCompatibleAgentModel(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        apiKey: 'sk-secret-key',
        model: 'kimi-k2.6',
        presetId: 'opencode-go',
        httpClient: client,
      );
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(
          model: model,
          kitApi: kitApi,
          includeTools: false,
        ),
        vanilla: VanillaCompletionClient(
          baseUrl: 'https://opencode.ai/zen/go/v1',
          apiKey: 'sk-secret-key',
          model: 'kimi-k2.6',
          presetId: 'opencode-go',
          httpClient: client,
        ),
        runtime: const ResolvedAgentRuntime(
          presetId: 'opencode-go',
          useFake: false,
          model: 'kimi-k2.6',
          apiKey: 'sk-secret-key',
        ),
      );
      final llmIds = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      final toolIds = kitApi.instantiate(
        'tools.list_kits',
        origin: const Offset(400, 0),
      );
      attachToolKit(
        kitApi: kitApi,
        toolObjectId: toolIds.first,
        llmBodyId: llmIds.last,
      );

      await controller.sendUser('kits', targetBodyId: llmIds.last);

      expect(sent, isNotNull);
      final tools = sent!['tools'] as List;
      expect(tools, hasLength(1));
      expect(
        (tools.single as Map)['function'],
        containsPair('name', 'list_kits'),
      );
      expect(
        kitApi.store.document.objectById(llmIds.last)!.props['reply'],
        'listed',
      );
    },
  );

  test(
    'context and conversation ride on the request and the reply is stored',
    () async {
      final sent = <Map<String, Object?>>[];
      final client = MockClient((request) async {
        sent.add(Map<String, Object?>.from(jsonDecode(request.body) as Map));
        final count = sent.length;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'reply $count'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
        vanilla: VanillaCompletionClient(
          baseUrl: 'https://opencode.ai/zen/go/v1',
          apiKey: 'sk-secret-key',
          model: 'deepseek-v4-flash',
          presetId: 'opencode-go',
          httpClient: client,
        ),
        runtime: const ResolvedAgentRuntime(
          presetId: 'opencode-go',
          useFake: false,
          model: 'deepseek-v4-flash',
          apiKey: 'sk-secret-key',
        ),
      );
      final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
      final text = kitApi.instantiate(
        boardTextKitId,
        origin: const Offset(0, 400),
      );
      final conversation = kitApi.instantiate(
        harnessConversationKitId,
        origin: const Offset(0, 640),
      );
      kitApi.updateProps(text.last, {'content': 'Texting from space'});
      connectTextToLlm(
        kitApi: kitApi,
        textObjectId: text.first,
        llmBodyId: llm.last,
        port: llmContextPort,
      );
      connectTextToLlm(
        kitApi: kitApi,
        textObjectId: conversation.first,
        llmBodyId: llm.last,
        port: llmConversationPort,
      );

      await controller.sendUser('hello', targetBodyId: llm.last);
      expect(sent.single['messages'], [
        {'role': 'system', 'content': 'Texting from space'},
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(
        conversationTurnsOf(
          kitApi.store.document.objectById(conversation.last)!,
        ),
        [
          const ConversationTurn(role: 'user', content: 'hello'),
          const ConversationTurn(role: 'assistant', content: 'reply 1'),
        ],
      );

      kitApi.updateProps(llm.last, {
        'model': '',
        'provider': '',
        'surface': '',
      });
      await controller.sendUser('again', targetBodyId: llm.last);
      expect(sent.last['messages'], [
        {'role': 'system', 'content': 'Texting from space'},
        {'role': 'user', 'content': 'hello'},
        {'role': 'assistant', 'content': 'reply 1'},
        {'role': 'user', 'content': 'again'},
      ]);
    },
  );

  test('Apply OpenCode Go luna builds a responses vanilla client', () async {
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    await controller.applySettings(
      providerId: 'opencode-go',
      model: 'gpt-5.6-luna',
      apiKey: 'oc-test',
    );
    expect(controller.vanilla, isA<VanillaResponsesClient>());
  });
}
