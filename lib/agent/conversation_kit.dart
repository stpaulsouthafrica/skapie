import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

const String turnsProp = 'turns';

List<ConversationTurn> conversationTurnsOf(SceneObject body) {
  return conversationTurnsFrom(body.props[turnsProp]);
}

String formatConversationTranscript(List<ConversationTurn> turns) {
  if (turns.isEmpty) {
    return '';
  }
  return [
    for (final turn in turns)
      '${turn.role == 'assistant' ? 'Assistant' : 'User'}\n${turn.content}',
  ].join('\n\n');
}

void clearConversation({required KitApi kitApi, required String bodyId}) {
  kitApi.updateProps(bodyId, {turnsProp: <Object?>[], 'content': ''});
}

SceneObject? conversationBody(SceneDocument document, SceneObject frame) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'body') {
      continue;
    }
    if (kitIdOf(object) != harnessConversationKitId) {
      continue;
    }
    if (kitChildBelongsToFrame(object, frame)) {
      return object;
    }
  }
  return null;
}

/// Append the turn that just ran. The cable decides which kit receives it.
void appendConversationExchange({
  required KitApi kitApi,
  required String bodyId,
  required String userText,
  required String assistantText,
  DateTime? userAt,
  DateTime? assistantAt,
}) {
  final body = kitApi.store.document.objectById(bodyId);
  if (body == null || kitIdOf(body) != harnessConversationKitId) {
    return;
  }
  final now = DateTime.now();
  final turns = [
    ...conversationTurnsOf(body),
    ConversationTurn(role: 'user', content: userText, at: userAt ?? now),
    ConversationTurn(
      role: 'assistant',
      content: assistantText,
      at: assistantAt ?? now,
    ),
  ];
  kitApi.updateProps(bodyId, {
    turnsProp: [for (final turn in turns) turn.toJson()],
    'content': formatConversationTranscript(turns),
  });
}
