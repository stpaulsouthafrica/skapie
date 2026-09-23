import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('multi-paragraph replies stay one assistant turn with timestamps', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final conversation = kitApi.instantiate(
      harnessConversationKitId,
      origin: Offset.zero,
    );
    final asked = DateTime.utc(2026, 9, 23, 18, 0);
    final answered = DateTime.utc(2026, 9, 23, 18, 1);
    const reply = 'Here is the breakdown:\n\n**Root level:**\n- logo.png';
    appendConversationExchange(
      kitApi: kitApi,
      bodyId: conversation.last,
      userText: 'What is in here?',
      assistantText: reply,
      userAt: asked,
      assistantAt: answered,
    );
    appendConversationExchange(
      kitApi: kitApi,
      bodyId: conversation.last,
      userText: 'Again',
      assistantText: 'Same.',
    );

    final turns = conversationTurnsOf(
      kitApi.store.document.objectById(conversation.last)!,
    );
    expect(turns.map((turn) => turn.role), [
      'user',
      'assistant',
      'user',
      'assistant',
    ]);
    expect(turns[1].content, reply);
    expect(turns[0].at, asked);
    expect(turns[1].at, answered);
    expect(turns[2].at, isNotNull);
    expect(chatMessages(userText: 'next', history: turns), hasLength(5));
  });

  test('clearConversation empties turns and the preview', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final conversation = kitApi.instantiate(
      harnessConversationKitId,
      origin: Offset.zero,
    );
    appendConversationExchange(
      kitApi: kitApi,
      bodyId: conversation.last,
      userText: 'hi',
      assistantText: 'hello',
    );
    clearConversation(kitApi: kitApi, bodyId: conversation.last);
    final body = kitApi.store.document.objectById(conversation.last)!;
    expect(conversationTurnsOf(body), isEmpty);
    expect(body.props['content'], '');
  });
}
