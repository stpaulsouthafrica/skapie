import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('starter kit.dart files register the four coding tools', () {
    final kitApi = createAppKitApi(store: SceneStore());
    expect(createKitAgentTools(kitApi).map((tool) => tool.name), [
      'edit',
      'read',
      'shell',
      'write',
    ]);
  });

  test('a tool the package did not register is unknown', () async {
    final kitApi = createAppKitApi(store: SceneStore());
    final session = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(
              id: 'c1',
              name: 'add_object',
              argumentsJson: '{"typeId":"box","x":0,"y":0}',
            ),
          ],
        ),
        const AgentModelReply(content: 'denied'),
      ]),
      kitApi: kitApi,
      tools: createKitAgentTools(kitApi),
    );

    await session.sendUser('add');

    expect(kitApi.store.document.objects, isEmpty);
    expect(
      session.messages
          .singleWhere((message) => message.role == AgentRole.tool)
          .content,
      contains('Unknown tool'),
    );
  });
}
