import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/agent/openai_compatible.dart';

void main() {
  test('OpenCode-style data id list maps to model infos without thinking', () {
    final models = parseAgentModelsCatalog({
      'data': [
        {'id': 'kimi-k2.6'},
        {'id': 'kimi-k2.6'},
        {'id': 'minimax-m2.5'},
      ],
    });
    expect(models.map((m) => m.id).toList(), ['kimi-k2.6', 'minimax-m2.5']);
    expect(models.first.displayName, 'kimi-k2.6');
    expect(models.first.thinkingLevels, isEmpty);
  });

  test('OpenRouter-style name + supported_efforts fills thinkingLevels', () {
    final models = parseAgentModelsCatalog({
      'data': [
        {
          'id': 'anthropic/claude-sonnet-4',
          'name': 'Anthropic: Claude Sonnet 4',
          'supported_efforts': ['low', 'medium', 'high'],
        },
      ],
    });
    expect(models, hasLength(1));
    expect(models.single.id, 'anthropic/claude-sonnet-4');
    expect(models.single.displayName, 'Anthropic: Claude Sonnet 4');
    expect(models.single.thinkingLevels, ['low', 'medium', 'high']);
  });

  test('OpenRouter reasoning.efforts list is accepted', () {
    final models = parseAgentModelsCatalog({
      'data': [
        {
          'id': 'openai/gpt-5',
          'name': 'GPT-5',
          'reasoning': {
            'efforts': ['minimal', 'low', 'medium', 'high'],
          },
        },
      ],
    });
    expect(models.single.thinkingLevels, ['minimal', 'low', 'medium', 'high']);
  });

  test('malformed catalog throws a typed error', () {
    expect(
      () => parseAgentModelsCatalog('nope'),
      throwsA(isA<AgentHttpException>()),
    );
    expect(
      () => parseAgentModelsCatalog({'data': 'x'}),
      throwsA(isA<AgentHttpException>()),
    );
  });

  test('fetchAgentModels GET success fills the list', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://opencode.ai/zen/go/v1/models');
      expect(request.headers['Authorization'], 'Bearer oc-test');
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'kimi-k2.6'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final models = await fetchAgentModels(
      baseUrl: 'https://opencode.ai/zen/go/v1/',
      apiKey: 'oc-test',
      httpClient: client,
    );
    expect(models.single.id, 'kimi-k2.6');
  });

  test('fetchAgentModels throws on 401', () async {
    final client = MockClient((request) async {
      return http.Response('unauthorized', 401);
    });
    await expectLater(
      fetchAgentModels(
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'bad',
        httpClient: client,
      ),
      throwsA(isA<AgentHttpException>()),
    );
  });
}
