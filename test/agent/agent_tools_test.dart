import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late SceneStore store;
  late KitApi kitApi;

  setUp(() {
    store = SceneStore();
    kitApi = createAppKitApi(store: store);
  });

  test('scripted add_object puts a box on the scene via KitApi', () async {
    final session = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(
              id: 'c1',
              name: 'add_object',
              argumentsJson: '{"typeId":"box","x":10,"y":20}',
            ),
          ],
        ),
        const AgentModelReply(content: 'Added a box.'),
      ]),
      kitApi: kitApi,
    );

    await session.sendUser('add a box');

    expect(store.document.objects, hasLength(1));
    expect(store.document.objects.single.type, 'box');
    expect(store.document.objects.single.x, 10);
    expect(store.document.objects.single.y, 20);
    expect(
      session.messages.where((m) => m.role == AgentRole.tool),
      hasLength(1),
    );
    expect(session.messages.last.role, AgentRole.assistant);
    expect(session.messages.last.content, 'Added a box.');
    expect(session.messages.last.toolCalls, isNull);
  });

  test('instantiate_kit demo.note-card adds two objects', () async {
    final session = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(
              id: 'c1',
              name: 'instantiate_kit',
              argumentsJson:
                  '{"kitId":"demo.note-card","originX":100,"originY":50}',
            ),
          ],
        ),
        const AgentModelReply(content: 'Spawned note card.'),
      ]),
      kitApi: kitApi,
    );

    await session.sendUser('note');

    expect(store.document.objects.map((o) => o.type), ['box', 'text']);
    expect(store.document.objects[1].x, 112);
    store.undo();
    expect(store.document.objects, hasLength(1));
    store.undo();
    expect(store.document.objects, isEmpty);
  });

  test(
    'unknown tool name is a tool error; scene unchanged; loop continues',
    () async {
      final session = AgentSession(
        model: ScriptedAgentModel([
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(id: 'c1', name: 'nope.tool', argumentsJson: '{}'),
            ],
          ),
          const AgentModelReply(content: 'I could not do that.'),
        ]),
        kitApi: kitApi,
      );

      await session.sendUser('nope');

      expect(store.document.objects, isEmpty);
      final tool = session.messages.singleWhere(
        (m) => m.role == AgentRole.tool,
      );
      expect(tool.toolCallId, 'c1');
      expect(tool.content, contains('Unknown tool'));
      expect(session.messages.last.content, 'I could not do that.');
    },
  );

  test(
    'unknown typeId in add_object is a tool error; scene unchanged',
    () async {
      final session = AgentSession(
        model: ScriptedAgentModel([
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 'c1',
                name: 'add_object',
                argumentsJson: '{"typeId":"nope.widget","x":0,"y":0}',
              ),
            ],
          ),
          const AgentModelReply(content: 'skipped'),
        ]),
        kitApi: kitApi,
      );

      await session.sendUser('bad type');

      expect(store.document.objects, isEmpty);
      expect(
        session.messages.singleWhere((m) => m.role == AgentRole.tool).content,
        contains('nope.widget'),
      );
    },
  );

  test('list_kits returns the demo kit', () async {
    final session = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(id: 'c1', name: 'list_kits', argumentsJson: '{}'),
          ],
        ),
        const AgentModelReply(content: 'listed'),
      ]),
      kitApi: kitApi,
    );

    await session.sendUser('kits');

    final tool = session.messages.singleWhere((m) => m.role == AgentRole.tool);
    expect(tool.content, contains('demo.note-card'));
    expect(tool.content, contains('Note card'));
  });

  test('bad JSON args become a tool error; sendUser does not throw', () async {
    final session = AgentSession(
      model: ScriptedAgentModel([
        const AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(
              id: 'c1',
              name: 'add_object',
              argumentsJson: 'not-json',
            ),
          ],
        ),
        const AgentModelReply(content: 'recovered'),
      ]),
      kitApi: kitApi,
    );

    await session.sendUser('bad json');

    expect(store.document.objects, isEmpty);
    expect(
      session.messages.singleWhere((m) => m.role == AgentRole.tool).content,
      contains('error'),
    );
    expect(session.messages.last.content, 'recovered');
  });

  test('max tool iterations appends limit message and finishes', () async {
    final replies = [
      for (var i = 0; i < 12; i++)
        AgentModelReply(
          content: '',
          toolCalls: [
            AgentToolCall(id: 'c$i', name: 'list_kits', argumentsJson: '{}'),
          ],
        ),
    ];
    final model = ScriptedAgentModel(replies);
    final session = AgentSession(
      model: model,
      kitApi: kitApi,
      maxToolIterations: 8,
    );

    await session.sendUser('loop');

    expect(model.completeCount, 8);
    expect(session.messages.last.role, AgentRole.assistant);
    expect(session.messages.last.content, 'Tool loop limit reached');
  });
}
