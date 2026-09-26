import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

const String compactedSummaryProp = 'compactedSummary';
const String compactedFromProp = 'compactedFrom';
const String compactedToProp = 'compactedTo';
const String compactedAtProp = 'compactedAt';

/// A derived summary that stands in for a span of earlier turns. The original
/// turns stay on the kit; this only changes what the next request sends.
class ConversationCompaction {
  const ConversationCompaction({
    required this.fromTurn,
    required this.toTurn,
    required this.summary,
    this.at,
  });

  final int fromTurn;
  final int toTurn;
  final String summary;
  final DateTime? at;

  bool get isEmpty => summary.trim().isEmpty || toTurn <= fromTurn;
}

ConversationCompaction? conversationCompactionOf(SceneObject body) {
  final summary = body.props[compactedSummaryProp]?.toString().trim() ?? '';
  final from = _intOf(body.props[compactedFromProp]);
  final to = _intOf(body.props[compactedToProp]);
  if (summary.isEmpty || from == null || to == null || to <= from) {
    return null;
  }
  return ConversationCompaction(
    fromTurn: from,
    toTurn: to,
    summary: summary,
    at: DateTime.tryParse(body.props[compactedAtProp]?.toString() ?? ''),
  );
}

/// The turns a request should send: the summary replaces its source span.
List<ConversationTurn> compactedHistory(
  List<ConversationTurn> turns,
  ConversationCompaction? compaction,
) {
  if (compaction == null || compaction.isEmpty) {
    return turns;
  }
  final from = compaction.fromTurn.clamp(0, turns.length);
  final to = compaction.toTurn.clamp(from, turns.length);
  return [
    ...turns.take(from),
    ConversationTurn(role: 'assistant', content: compaction.summary),
    ...turns.skip(to),
  ];
}

/// Store a summary that stands in for turns [fromTurn, toTurn).
void compactConversation({
  required KitApi kitApi,
  required String bodyId,
  required int fromTurn,
  required int toTurn,
  required String summary,
  DateTime? at,
}) {
  kitApi.updateProps(bodyId, {
    compactedSummaryProp: summary,
    compactedFromProp: fromTurn,
    compactedToProp: toTurn,
    compactedAtProp: (at ?? DateTime.now()).toUtc().toIso8601String(),
  });
}

/// Drop the summary. The original turns were never touched.
void clearConversationCompaction({
  required KitApi kitApi,
  required String bodyId,
}) {
  kitApi.updateProps(bodyId, {
    compactedSummaryProp: '',
    compactedFromProp: 0,
    compactedToProp: 0,
    compactedAtProp: '',
  });
}

/// Compact every turn except the newest [keep]. A plain, repeatable digest.
bool compactOldestTurns({
  required KitApi kitApi,
  required String bodyId,
  int keep = 2,
  int perTurn = 140,
}) {
  final body = kitApi.store.document.objectById(bodyId);
  if (body == null) {
    return false;
  }
  final turns = conversationTurnsOf(body);
  if (turns.length <= keep) {
    return false;
  }
  final to = turns.length - keep;
  compactConversation(
    kitApi: kitApi,
    bodyId: bodyId,
    fromTurn: 0,
    toTurn: to,
    summary: condenseTurns(turns, to: to, perTurn: perTurn),
  );
  return true;
}

/// Short, role-labelled digest of turns [from, to). Deterministic.
String condenseTurns(
  List<ConversationTurn> turns, {
  int from = 0,
  required int to,
  int perTurn = 140,
}) {
  final buffer = StringBuffer('[Earlier turns, condensed]');
  for (var i = from; i < to && i < turns.length; i++) {
    final turn = turns[i];
    final text = turn.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    final clipped = text.length <= perTurn
        ? text
        : '${text.substring(0, perTurn)}...';
    buffer.write('\n${turn.role == 'assistant' ? 'Assistant' : 'User'}: $clipped');
  }
  return buffer.toString();
}

int? _intOf(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value');
}
