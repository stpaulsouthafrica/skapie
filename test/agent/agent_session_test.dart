import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  test('new session starts with the default system message', () {
    final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);

    expect(session.messages, hasLength(1));
    expect(session.messages.single.role, AgentRole.system);
    expect(session.messages.single.content, defaultAgentSystemPrompt);
  });

  test(
    'sendUser with FakeAgentModel appends user then echoed assistant',
    () async {
      final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);

      await session.sendUser('hi');

      expect(session.messages.map((m) => m.role), [
        AgentRole.system,
        AgentRole.user,
        AgentRole.assistant,
      ]);
      expect(session.messages[1].content, 'hi');
      expect(session.messages[2].content, 'Echo: hi');
    },
  );

  test('events fire started, message, message, finished', () async {
    final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);
    final events = <AgentEvent>[];
    final sub = session.events.listen(events.add);

    await session.sendUser('ping');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(events, hasLength(4));
    expect(events[0], isA<AgentTurnStarted>());
    expect(events[1], isA<AgentMessageAppended>());
    expect((events[1] as AgentMessageAppended).message.role, AgentRole.user);
    expect(events[2], isA<AgentMessageAppended>());
    expect(
      (events[2] as AgentMessageAppended).message.role,
      AgentRole.assistant,
    );
    expect(events[3], isA<AgentTurnFinished>());
  });

  test(
    'model throw keeps user message, adds no assistant, emits failed',
    () async {
      final session = AgentSession(model: _ThrowingModel(), kitApi: kitApi);
      final events = <AgentEvent>[];
      final sub = session.events.listen(events.add);

      await expectLater(
        session.sendUser('keep me'),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(session.messages.map((m) => m.role), [
        AgentRole.system,
        AgentRole.user,
      ]);
      expect(session.messages.last.content, 'keep me');
      expect(events.whereType<AgentTurnFailed>(), hasLength(1));
      expect(
        events.whereType<AgentMessageAppended>().single.message.role,
        AgentRole.user,
      );
      expect(events.whereType<AgentTurnFinished>(), isEmpty);
    },
  );
}

class _ThrowingModel implements AgentModel {
  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) {
    throw StateError('boom');
  }
}
