import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

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
      throwsA(
        isA<AgentHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.body, 'body', 'nope')
            .having((e) => e.toString(), 'toString', contains('HTTP 401')),
      ),
    );
    expect(model.lastDiagnostic, isNotNull);
    expect(model.lastDiagnostic!.statusCode, 401);
    expect(model.lastDiagnostic!.responseBody, contains('nope'));
    expect(model.lastDiagnostic!.summary, isNot(contains('bad')));
  });

  test('tools are omitted when the tool list is empty', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body.containsKey('tools'), isFalse);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'plain'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final model = OpenAiCompatibleAgentModel(
      baseUrl: 'https://opencode.ai/zen/go/v1',
      apiKey: 'oc-secret-should-not-appear',
      model: 'muse-spark-1.2-contributor',
      httpClient: client,
    );
    final reply = await model.complete(
      messages: const [AgentMessage(role: AgentRole.user, content: 'hi')],
    );
    expect(reply.content, 'plain');
    expect(model.lastDiagnostic!.toolNames, isEmpty);
    expect(model.lastDiagnostic!.summary, isNot(contains('oc-secret')));
  });

  test('tools are included with object schemas when provided', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body['tools'], isNotEmpty);
      expect(body.containsKey('reasoning'), isFalse);
      final tool = (body['tools'] as List).first as Map;
      expect(tool['type'], 'function');
      expect(
        (tool['function'] as Map)['parameters'],
        containsPair('type', 'object'),
      );
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
    final model = OpenAiCompatibleAgentModel(
      baseUrl: 'https://opencode.ai/zen/go/v1',
      apiKey: 'oc-test',
      model: 'kimi-k2.6',
      httpClient: client,
    );
    await model.complete(
      messages: const [AgentMessage(role: AgentRole.user, content: 'hi')],
      tools: createKitAgentTools(createAppKitApi(store: SceneStore())),
    );
    expect(model.lastDiagnostic!.toolNames, contains('list_kits'));
  });

  test('OpenRouter reasoning effort is sent when set', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body['reasoning'], {'effort': 'high'});
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
    final model = OpenAiCompatibleAgentModel(
      baseUrl: 'https://openrouter.ai/api/v1',
      apiKey: 'or-test',
      model: 'anthropic/claude-sonnet-4',
      httpClient: client,
      reasoningEffort: 'high',
    );
    await model.complete(
      messages: const [AgentMessage(role: AgentRole.user, content: 'hi')],
    );
  });
}
