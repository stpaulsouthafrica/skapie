/// One earlier turn the model should treat as its own conversation.
class ConversationTurn {
  const ConversationTurn({required this.role, required this.content});

  /// `user` or `assistant`.
  final String role;
  final String content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};

  @override
  bool operator ==(Object other) {
    return other is ConversationTurn &&
        other.role == role &&
        other.content == content;
  }

  @override
  int get hashCode => Object.hash(role, content);
}

List<ConversationTurn> conversationTurnsFrom(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final turns = <ConversationTurn>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final role = item['role']?.toString().trim() ?? '';
    final content = item['content']?.toString() ?? '';
    if ((role != 'user' && role != 'assistant') || content.trim().isEmpty) {
      continue;
    }
    turns.add(ConversationTurn(role: role, content: content));
  }
  return turns;
}

/// Messages for one completion: background, then earlier turns, then the ask.
List<Map<String, Object?>> chatMessages({
  required String userText,
  String systemText = '',
  List<ConversationTurn> history = const [],
}) {
  final system = systemText.trim();
  return [
    if (system.isNotEmpty) {'role': 'system', 'content': system},
    for (final turn in history)
      if (turn.content.trim().isNotEmpty)
        {'role': turn.role, 'content': turn.content},
    {'role': 'user', 'content': userText},
  ];
}
