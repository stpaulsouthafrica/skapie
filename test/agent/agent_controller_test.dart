import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/kit_api/kit_api.dart';
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
}
