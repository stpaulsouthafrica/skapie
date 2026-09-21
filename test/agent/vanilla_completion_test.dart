import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/vanilla_completion.dart';

void main() {
  test(
    'vanilla completion sends only model and a single user message',
    () async {
      late Map<String, Object?> sent;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://opencode.ai/zen/go/v1/chat/completions',
        );
        expect(request.headers['Authorization'], 'Bearer oc-secret');
        expect(request.headers['x-opencode-session'], 'agent_1');
        expect(request.headers['User-Agent'], 'skapie/0.1');
        sent = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'plain reply'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final vanilla = VanillaCompletionClient(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        apiKey: 'oc-secret',
        model: 'kimi-k2.6',
        presetId: 'opencode-go',
        headers: const {
          'x-opencode-session': 'agent_1',
          'User-Agent': 'skapie/0.1',
        },
        httpClient: client,
      );
      final reply = await vanilla.complete(userText: 'hello world');
      expect(reply, 'plain reply');
      expect(sent.keys, unorderedEquals(['model', 'messages']));
      expect(sent['model'], 'kimi-k2.6');
      expect(sent['messages'], [
        {'role': 'user', 'content': 'hello world'},
      ]);
      expect(sent.containsKey('tools'), isFalse);
      expect(sent.containsKey('reasoning'), isFalse);
      expect(vanilla.lastDiagnostic!.toolNames, isEmpty);
      expect(vanilla.lastDiagnostic!.reasoningAttached, isFalse);
      expect(vanilla.lastDiagnostic!.summary, isNot(contains('oc-secret')));
    },
  );

  test(
    'vanilla completion preserves HTTP status and body without the key',
    () async {
      final client = MockClient((request) async {
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
      await expectLater(
        vanilla.complete(userText: 'hello'),
        throwsA(
          isA<AgentHttpException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.body, 'body', contains('Internal server error')),
        ),
      );
      expect(vanilla.lastDiagnostic!.statusCode, 500);
      expect(vanilla.lastDiagnostic!.toolNames, isEmpty);
      expect(vanilla.lastDiagnostic!.summary, isNot(contains('sk-secret-key')));
    },
  );
}
