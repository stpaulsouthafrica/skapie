import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/vanilla_completion.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/providers/vanilla_responses.dart';
import 'package:skapie/scene/scene.dart';

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
      expect(controller.session.messages.single.role, AgentRole.system);
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

      await controller.sendUser('again');
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
      await expectLater(
        controller.sendUser('hello'),
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
