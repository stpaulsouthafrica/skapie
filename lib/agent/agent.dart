import 'dart:async';

const String defaultAgentSystemPrompt =
    'You are Skapie\'s canvas agent. You talk about the canvas and scene. Tools come later.';

enum AgentRole { system, user, assistant, tool }

/// Placeholder for Phase 9.1. Unused by the Phase 9 loop.
class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
}

class AgentMessage {
  const AgentMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
  });

  final AgentRole role;
  final String content;
  final List<AgentToolCall>? toolCalls;
  final String? toolCallId;
}

class AgentModelReply {
  const AgentModelReply({required this.content, this.toolCalls});

  final String content;
  final List<AgentToolCall>? toolCalls;
}

abstract class AgentModel {
  Future<AgentModelReply> complete({required List<AgentMessage> messages});
}

/// Deterministic stand-in. Replies `Echo: <last user text>`. No network.
class FakeAgentModel implements AgentModel {
  const FakeAgentModel();

  @override
  Future<AgentModelReply> complete({required List<AgentMessage> messages}) async {
    final lastUser = messages.lastWhere(
      (message) => message.role == AgentRole.user,
      orElse: () => const AgentMessage(role: AgentRole.user, content: ''),
    );
    return AgentModelReply(content: 'Echo: ${lastUser.content}');
  }
}

sealed class AgentEvent {
  const AgentEvent();
}

class AgentTurnStarted extends AgentEvent {
  const AgentTurnStarted();
}

class AgentMessageAppended extends AgentEvent {
  const AgentMessageAppended(this.message);

  final AgentMessage message;
}

class AgentTurnFinished extends AgentEvent {
  const AgentTurnFinished();
}

class AgentTurnFailed extends AgentEvent {
  const AgentTurnFailed(this.error);

  final Object error;
}

/// One conversation. Does not touch the scene or KitApi.
class AgentSession {
  AgentSession({required this.model, String? systemPrompt})
    : _messages = [
        AgentMessage(
          role: AgentRole.system,
          content: systemPrompt ?? defaultAgentSystemPrompt,
        ),
      ];

  final AgentModel model;
  final List<AgentMessage> _messages;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  Stream<AgentEvent> get events => _events.stream;

  /// Append a user message, call the model, append the assistant reply.
  ///
  /// On model failure: user message is kept, no assistant message is added,
  /// [AgentTurnFailed] is emitted, then the error is rethrown.
  Future<void> sendUser(String text) async {
    final user = AgentMessage(role: AgentRole.user, content: text);
    _messages.add(user);
    _events.add(const AgentTurnStarted());
    _events.add(AgentMessageAppended(user));
    try {
      final reply = await model.complete(
        messages: List.unmodifiable(_messages),
      );
      final assistant = AgentMessage(
        role: AgentRole.assistant,
        content: reply.content,
      );
      _messages.add(assistant);
      _events.add(AgentMessageAppended(assistant));
      _events.add(const AgentTurnFinished());
    } catch (error) {
      _events.add(AgentTurnFailed(error));
      rethrow;
    }
  }
}
