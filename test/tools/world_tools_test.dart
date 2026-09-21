import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('createWorldTools registers one AgentTool per world file', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final tools = createWorldTools(kitApi);
    expect(tools.map((tool) => tool.name), [
      'list_kits',
      'get_kit',
      'instantiate_kit',
      'add_object',
      'remove_object',
      'update_frame',
      'update_props',
      'set_locked',
      'save_kit',
      'reload_packages',
      'register_kit',
    ]);
    expect(createKitAgentTools(kitApi).map((tool) => tool.name), [
      for (final tool in tools) tool.name,
    ]);
  });

  test('session with only list_kits cannot add_object', () async {
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
      tools: [
        for (final tool in createWorldTools(kitApi))
          if (tool.name == 'list_kits') tool,
      ],
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
