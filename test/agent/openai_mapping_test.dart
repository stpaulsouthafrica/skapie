import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('session messages map to OpenAI roles including tool_calls', () {
    const messages = [
      AgentMessage(role: AgentRole.system, content: 'sys'),
      AgentMessage(role: AgentRole.user, content: 'add a box'),
      AgentMessage(
        role: AgentRole.assistant,
        content: '',
        toolCalls: [
          AgentToolCall(
            id: 'call_1',
            name: 'add_object',
            argumentsJson: '{"typeId":"box"}',
          ),
        ],
      ),
      AgentMessage(
        role: AgentRole.tool,
        content: '{"id":"o1"}',
        toolCallId: 'call_1',
      ),
    ];

    final json = openaiMessagesFromSession(messages);
    expect(json, [
      {'role': 'system', 'content': 'sys'},
      {'role': 'user', 'content': 'add a box'},
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'add_object', 'arguments': '{"typeId":"box"}'},
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'call_1', 'content': '{"id":"o1"}'},
    ]);
  });

  test('choice message with tool_calls maps to AgentModelReply', () {
    final reply = openaiReplyFromMessage({
      'content': '',
      'tool_calls': [
        {
          'id': 'c2',
          'type': 'function',
          'function': {'name': 'list_kits', 'arguments': '{}'},
        },
      ],
    });
    expect(reply.content, '');
    expect(reply.toolCalls, hasLength(1));
    expect(reply.toolCalls!.single.id, 'c2');
    expect(reply.toolCalls!.single.name, 'list_kits');
    expect(reply.toolCalls!.single.argumentsJson, '{}');
  });

  test('choice message with text maps to content-only reply', () {
    final reply = openaiReplyFromMessage({'content': 'Added a box.'});
    expect(reply.content, 'Added a box.');
    expect(reply.toolCalls, isNull);
  });

  test('kit tools send object parameters, never an empty schema', () {
    final mapped = openaiToolsFromAgent(
      createKitAgentTools(createAppKitApi(store: SceneStore())),
    );
    expect(mapped, isNotEmpty);
    for (final tool in mapped) {
      final function = tool['function'] as Map;
      final parameters = function['parameters'] as Map;
      expect(parameters['type'], 'object');
      if (function['name'] == 'add_object') {
        expect((parameters['properties'] as Map).containsKey('typeId'), isTrue);
        expect(parameters['required'], contains('typeId'));
      }
      if (function['name'] == 'list_kits') {
        expect(parameters['properties'], isEmpty);
      }
    }
  });

  test('normalize base URL for chat completions', () {
    expect(
      openaiChatCompletionsUrl('https://api.openai.com/v1'),
      'https://api.openai.com/v1/chat/completions',
    );
    expect(
      openaiChatCompletionsUrl('https://api.openai.com/v1/'),
      'https://api.openai.com/v1/chat/completions',
    );
  });
}
