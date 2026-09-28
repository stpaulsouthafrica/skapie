import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/run_control.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late SceneStore store;
  late KitApi kitApi;

  setUp(() {
    store = SceneStore();
    kitApi = createAppKitApi(store: store);
  });

  test('bad JSON args become a tool error; sendUser does not throw', () async {
    final session = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(id: 'c1', name: 'read', argumentsJson: 'not-json'),
          ],
        ),
        const AgentModelReply(content: 'recovered'),
      ]),
      kitApi: kitApi,
      tools: createKitAgentTools(kitApi),
    );

    await session.sendUser('bad json');

    expect(store.document.objects, isEmpty);
    expect(
      session.messages.singleWhere((m) => m.role == AgentRole.tool).content,
      contains('error'),
    );
    expect(session.messages.last.content, 'recovered');
  });

  test('session with includeTools false does not send tools', () async {
    var sawTools = false;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      sawTools = body.containsKey('tools');
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'plain'}},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final session = AgentSession(
      model: OpenAiCompatibleAgentModel(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        apiKey: 'oc-test',
        model: 'kimi-k2.6',
        httpClient: client,
      ),
      kitApi: kitApi,
      tools: createKitAgentTools(kitApi),
      includeTools: false,
    );
    await session.sendUser('hi');
    expect(sawTools, isFalse);
    expect(session.messages.last.content, 'plain');
  });

  test('max tool iterations fails with a named limit', () async {
    final replies = [
      for (var i = 0; i < 12; i++)
        AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(
              id: 'c$i',
              name: 'read',
              argumentsJson: '{"action":"list"}',
            ),
          ],
        ),
    ];
    final session = AgentSession(
      model: ScriptedAgentModel(replies),
      kitApi: kitApi,
      tools: createKitAgentTools(kitApi),
      maxToolIterations: 8,
    );

    await expectLater(
      session.sendUser('loop'),
      throwsA(isA<RunLimitReached>()),
    );
    expect(session.messages.last.role, AgentRole.tool);
  });
}
