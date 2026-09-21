import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_completion.dart';
import 'package:skapie/providers/unverified_vanilla.dart';
import 'package:skapie/providers/vanilla_extract.dart';
import 'package:skapie/providers/vanilla_messages.dart';
import 'package:skapie/providers/vanilla_responses.dart';

const _go = 'https://opencode.ai/zen/go/v1';

ResolvedAgentRuntime _live(String model) {
  return ResolvedAgentRuntime(
    presetId: 'opencode-go',
    useFake: false,
    baseUrl: _go,
    apiKey: 'oc-secret',
    model: model,
  );
}

void main() {
  test('completions vanilla body is still only model + user message', () async {
    late Map<String, Object?> sent;
    late Uri url;
    final client = MockClient((request) async {
      url = request.url;
      sent = Map<String, Object?>.from(jsonDecode(request.body) as Map);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'ok'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final vanilla = buildVanillaClient(
      runtime: _live('deepseek-v4-flash'),
      sessionId: 'agent_1',
      httpClient: client,
    );
    expect(vanilla, isA<VanillaCompletionClient>());
    expect(await vanilla!.complete(userText: 'hello'), 'ok');
    expect(url.toString(), '$_go/chat/completions');
    expect(sent.keys, unorderedEquals(['model', 'messages']));
    expect(sent['model'], 'deepseek-v4-flash');
    expect(sent['messages'], [
      {'role': 'user', 'content': 'hello'},
    ]);
    expect(vanilla.lastDiagnostic!.surface, 'completions');
    expect(vanilla.lastDiagnostic!.summary, contains('completions'));
    expect(vanilla.lastDiagnostic!.summary, isNot(contains('oc-secret')));
  });

  test('responses vanilla posts model + input only', () async {
    late Map<String, Object?> sent;
    late http.BaseRequest request;
    final client = MockClient((req) async {
      request = req;
      sent = Map<String, Object?>.from(jsonDecode(req.body) as Map);
      return http.Response(
        jsonEncode({
          'output_text': 'from shortcut',
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'from items'},
              ],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final vanilla = buildVanillaClient(
      runtime: _live('gpt-5.6-luna'),
      sessionId: 'agent_1',
      httpClient: client,
    );
    expect(vanilla, isA<VanillaResponsesClient>());
    expect(await vanilla!.complete(userText: 'hello luna'), 'from shortcut');
    expect(request.url.toString(), '$_go/responses');
    expect(request.headers['Authorization'], 'Bearer oc-secret');
    expect(request.headers['x-opencode-session'], 'agent_1');
    expect(request.headers['User-Agent'], 'skapie/0.1');
    expect(sent.keys, unorderedEquals(['model', 'input']));
    expect(sent['model'], 'gpt-5.6-luna');
    expect(sent['input'], 'hello luna');
    expect(sent.containsKey('tools'), isFalse);
    expect(sent.containsKey('instructions'), isFalse);
    expect(vanilla.lastDiagnostic!.surface, 'responses');
    expect(vanilla.lastDiagnostic!.summary, contains('responses'));
  });

  test('grok-4.6 routes to responses', () {
    expect(
      buildVanillaClient(runtime: _live('grok-4.6')),
      isA<VanillaResponsesClient>(),
    );
  });

  test(
    'messages vanilla posts model, max_tokens, and a user message',
    () async {
      late Map<String, Object?> sent;
      late http.BaseRequest request;
      final client = MockClient((req) async {
        request = req;
        sent = Map<String, Object?>.from(jsonDecode(req.body) as Map);
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'from messages'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final vanilla = buildVanillaClient(
        runtime: _live('minimax-m3'),
        sessionId: 'agent_1',
        httpClient: client,
      );
      expect(vanilla, isA<VanillaMessagesClient>());
      expect(await vanilla!.complete(userText: 'hello m3'), 'from messages');
      expect(request.url.toString(), '$_go/messages');
      expect(request.headers['Authorization'], 'Bearer oc-secret');
      expect(request.headers['x-api-key'], 'oc-secret');
      expect(request.headers.containsKey('anthropic-version'), isFalse);
      expect(sent.keys, unorderedEquals(['model', 'max_tokens', 'messages']));
      expect(sent['model'], 'minimax-m3');
      expect(sent['max_tokens'], 1024);
      expect(sent['messages'], [
        {'role': 'user', 'content': 'hello m3'},
      ]);
      expect(sent.containsKey('tools'), isFalse);
      expect(sent.containsKey('system'), isFalse);
      expect(vanilla.lastDiagnostic!.surface, 'messages');
    },
  );

  test('unknown OpenCode Go id is not posted as completions', () async {
    var posted = false;
    final client = MockClient((request) async {
      posted = true;
      return http.Response('should not run', 200);
    });
    final vanilla = buildVanillaClient(
      runtime: _live('brand-new-go-model'),
      httpClient: client,
    );
    expect(vanilla, isA<UnverifiedVanillaClient>());
    await expectLater(
      vanilla!.complete(userText: 'hello'),
      throwsA(
        isA<AgentHttpException>().having(
          (error) => error.message,
          'message',
          contains('not in the Skapie catalog yet'),
        ),
      ),
    );
    expect(posted, isFalse);
    expect(vanilla.lastDiagnostic!.surface, 'unverified');
  });

  test('responses extract prefers output_text then message items', () {
    expect(
      extractResponsesOutputText({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'item text'},
            ],
          },
        ],
      }),
      'item text',
    );
  });
}
