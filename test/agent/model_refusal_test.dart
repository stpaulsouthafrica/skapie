import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/messages_agent_model.dart';
import 'package:skapie/agent/model_refusal.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/responses_agent_model.dart';
import 'package:skapie/agent/run_error.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/providers/vanilla_completion.dart';
import 'package:skapie/providers/vanilla_extract.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('explicit refusals from each provider surface use one category', () {
    final reply = {
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'refusal', 'refusal': 'No'},
          ],
        },
      ],
    };
    final message = {
      'stop_reason': 'refusal',
      'content': [
        {'type': 'text', 'text': 'No'},
      ],
    };
    for (final parse in <void Function()>[
      () => openaiReplyFromMessage({'content': null, 'refusal': 'No'}),
      () => responsesReplyFromBody(reply),
      () => extractResponsesOutputText(reply),
      () => messagesReplyFromBody(message),
      () => extractAnthropicMessageText(message),
    ]) {
      expect(parse, throwsA(isA<ModelRefusalException>()));
    }
    expect(
      classifyRunError(const ModelRefusalException()),
      RunErrorKind.modelRefusal,
    );
  });

  test(
    'refusal in HTTP 200 fails a tool run without publishing draft text',
    () async {
      final api = createAppKitApi(store: SceneStore());
      final model = OpenAiCompatibleAgentModel(
        baseUrl: 'https://example.test/v1',
        apiKey: 'test-key',
        model: 'test-model',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': null, 'refusal': 'No'},
                },
              ],
            }),
            200,
          ),
        ),
      );
      final session = AgentSession(model: model, kitApi: api);
      await expectLater(
        session.sendUser('ask'),
        throwsA(isA<ModelRefusalException>()),
      );
      expect(
        session.messages.where(
          (message) => message.role == AgentRole.assistant,
        ),
        isEmpty,
      );
    },
  );

  test('plain completion rejects an HTTP 200 refusal', () async {
    final vanilla = VanillaCompletionClient(
      baseUrl: 'https://example.test/v1',
      apiKey: 'test-key',
      model: 'test-model',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': null, 'refusal': 'No'},
              },
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(
      vanilla.complete(userText: 'ask'),
      throwsA(isA<ModelRefusalException>()),
    );
  });
}
