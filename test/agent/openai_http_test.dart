import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/openai_compatible.dart';

void main() {
  test('OpenAiCompatibleAgentModel parses a success response', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(request.headers['Authorization'], 'Bearer sk-test');
      expect(request.headers['Content-Type'], contains('application/json'));
      final body = jsonDecode(request.body) as Map;
      expect(body['model'], 'gpt-4o-mini');
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'Hello from mock'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final model = OpenAiCompatibleAgentModel(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-test',
      model: 'gpt-4o-mini',
      httpClient: client,
    );
    final reply = await model.complete(
      messages: const [AgentMessage(role: AgentRole.user, content: 'hi')],
    );
    expect(reply.content, 'Hello from mock');
    expect(reply.toolCalls, isNull);
  });

  test('OpenAiCompatibleAgentModel throws on non-2xx', () async {
    final client = MockClient((request) async {
      return http.Response('nope', 401);
    });
    final model = OpenAiCompatibleAgentModel(
      baseUrl: 'https://api.openai.com/v1/',
      apiKey: 'bad',
      model: 'gpt-4o-mini',
      httpClient: client,
    );
    await expectLater(
      model.complete(
        messages: const [AgentMessage(role: AgentRole.user, content: 'hi')],
      ),
      throwsA(isA<AgentHttpException>()),
    );
  });
}
