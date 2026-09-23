/// What one LLM's latest run actually touched, in this session only.
class LlmRunUse {
  LlmRunUse({
    required this.bodyId,
    required this.startedAt,
    Set<String> readPorts = const {},
    Map<String, DateTime> toolCalls = const {},
    this.readConversation = false,
    this.wroteOutputAt,
    this.wroteConversationAt,
    this.finishedAt,
  }) : readPorts = Set.of(readPorts),
       toolCalls = Map.of(toolCalls);

  final String bodyId;
  final DateTime startedAt;

  /// Input ports whose value went into the request.
  final Set<String> readPorts;

  /// Tool frame id → when that tool was last called in this run.
  final Map<String, DateTime> toolCalls;
  bool readConversation;
  DateTime? wroteOutputAt;
  DateTime? wroteConversationAt;
  DateTime? finishedAt;
}
