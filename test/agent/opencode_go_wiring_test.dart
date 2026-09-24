import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/providers/model_surface.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';
import 'package:skapie/providers/vanilla_completion.dart';
import 'package:skapie/providers/vanilla_messages.dart';
import 'package:skapie/providers/vanilla_responses.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/world/kits.dart';

import 'agent_controller_test.dart';

void main() {
  const base = 'https://opencode.ai/zen/go/v1';

  String pathFor(ModelSurface surface) => switch (surface) {
    ModelSurface.completions => '/chat/completions',
    ModelSurface.responses => '/responses',
    ModelSurface.messages => '/messages',
  };

  test('every OpenCode Go model has a vanilla client for its surface', () {
    expect(opencodeGoCatalog, isNotEmpty);
    for (final model in opencodeGoCatalog) {
      final client = buildVanillaClient(
        runtime: ResolvedAgentRuntime(
          presetId: 'opencode-go',
          useFake: false,
          baseUrl: base,
          apiKey: 'k',
          model: model.id,
        ),
      );
      expect(client, switch (model.surface) {
        ModelSurface.completions => isA<VanillaCompletionClient>(),
        ModelSurface.responses => isA<VanillaResponsesClient>(),
        ModelSurface.messages => isA<VanillaMessagesClient>(),
      }, reason: model.id);
    }
  });

  test(
    'every OpenCode Go model with a tool posts to its catalog endpoint',
    () async {
      final posted = <String, String>{};
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        posted[body['model'] as String] = request.url.path;
        final path = request.url.path;
        final payload = path.endsWith('/responses')
            ? {'output_text': 'ok'}
            : path.endsWith('/messages')
            ? {
                'content': [
                  {'type': 'text', 'text': 'ok'},
                ],
              }
            : {
                'choices': [
                  {
                    'message': {'content': 'ok'},
                  },
                ],
              };
        return http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final kitApi = createAppKitApi(store: SceneStore());
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(
          model: OpenAiCompatibleAgentModel(
            baseUrl: base,
            apiKey: 'k',
            model: 'kimi-k2.6',
            presetId: 'opencode-go',
            httpClient: client,
          ),
          kitApi: kitApi,
        ),
        runtime: const ResolvedAgentRuntime(
          presetId: 'opencode-go',
          useFake: false,
          baseUrl: base,
          apiKey: 'k',
          model: 'kimi-k2.6',
        ),
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

      for (final model in opencodeGoCatalog) {
        kitApi.updateProps(llm.last, {'model': model.id});
        await controller.sendUser('go', targetBodyId: llm.last);
        expect(
          posted[model.id],
          endsWith(pathFor(model.surface)),
          reason: model.id,
        );
      }
    },
  );
}
