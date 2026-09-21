import 'dart:async';

import 'package:skapie/agent/agent_tool.dart';
import 'package:skapie/agent/agent_tool_dispatcher.dart';
import 'package:skapie/agent/kit_agent_tools.dart';
import 'package:skapie/kit_api/kit_api.dart';

export 'package:skapie/agent/agent_tool.dart';
export 'package:skapie/agent/agent_tool_dispatcher.dart';
export 'package:skapie/agent/kit_agent_tools.dart';

const String defaultAgentSystemPrompt =
    'You are Skapie\'s canvas agent. Use kit tools to change the scene. '
    'Prefer instantiate_kit, list_kits, and add_object rather than inventing UI. '
    'Say kit, kit recipe, or kit package — never bare "recipe".';

const int defaultMaxToolIterations = 8;

enum AgentRole { system, user, assistant, tool }

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
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  });
}

/// Deterministic stand-in. Replies `Echo: <last user text>`. No network.
class FakeAgentModel implements AgentModel {
  const FakeAgentModel();

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    final lastUser = messages.lastWhere(
      (message) => message.role == AgentRole.user,
      orElse: () => const AgentMessage(role: AgentRole.user, content: ''),
    );
    return AgentModelReply(content: 'Echo: ${lastUser.content}');
  }
}

/// Dequeues a fixed list of replies. For tests; no network.
class ScriptedAgentModel implements AgentModel {
  ScriptedAgentModel(List<AgentModelReply> replies)
    : _replies = List<AgentModelReply>.of(replies);

  final List<AgentModelReply> _replies;
  var completeCount = 0;

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    if (completeCount >= _replies.length) {
      throw StateError('No more scripted replies');
    }
    return _replies[completeCount++];
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

/// One conversation. Scene mutations go through [kitApi] tools only.
class AgentSession {
  AgentSession({
    required this.model,
    required this.kitApi,
    String? systemPrompt,
    String? id,
    this.maxToolIterations = defaultMaxToolIterations,
    this.includeTools = true,
  }) : id = id ?? 'agent_${DateTime.now().microsecondsSinceEpoch}',
       _tools = createKitAgentTools(kitApi),
       _messages = [
         AgentMessage(
           role: AgentRole.system,
           content: systemPrompt ?? defaultAgentSystemPrompt,
         ),
       ] {
    _dispatcher = AgentToolDispatcher(_tools);
  }

  final String id;

  final AgentModel model;
  final KitApi kitApi;
  final int maxToolIterations;
  final bool includeTools;
  final List<AgentTool> _tools;
  late final AgentToolDispatcher _dispatcher;
  final List<AgentMessage> _messages;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  Stream<AgentEvent> get events => _events.stream;

  /// Append a user message and run the model/tool loop.
  ///
  /// On model failure: user message is kept, [AgentTurnFailed] is emitted,
  /// then the error is rethrown. Tool dispatch errors become tool messages.
  Future<void> sendUser(String text) async {
    final user = AgentMessage(role: AgentRole.user, content: text);
    _messages.add(user);
    _events.add(const AgentTurnStarted());
    _events.add(AgentMessageAppended(user));
    try {
      for (var i = 0; i < maxToolIterations; i++) {
        final reply = await model.complete(
          messages: List.unmodifiable(_messages),
          tools: includeTools ? List.unmodifiable(_tools) : const <AgentTool>[],
        );
        final calls = reply.toolCalls;
        if (calls == null || calls.isEmpty) {
          final assistant = AgentMessage(
            role: AgentRole.assistant,
            content: reply.content,
          );
          _messages.add(assistant);
          _events.add(AgentMessageAppended(assistant));
          _events.add(const AgentTurnFinished());
          return;
        }
        final assistant = AgentMessage(
          role: AgentRole.assistant,
          content: reply.content,
          toolCalls: calls,
        );
        _messages.add(assistant);
        _events.add(AgentMessageAppended(assistant));
        for (final call in calls) {
          final result = await _dispatcher.dispatch(
            call.name,
            call.argumentsJson,
          );
          final toolMessage = AgentMessage(
            role: AgentRole.tool,
            content: result.content,
            toolCallId: call.id,
          );
          _messages.add(toolMessage);
          _events.add(AgentMessageAppended(toolMessage));
        }
      }
      const limit = AgentMessage(
        role: AgentRole.assistant,
        content: 'Tool loop limit reached',
      );
      _messages.add(limit);
      _events.add(const AgentMessageAppended(limit));
      _events.add(const AgentTurnFinished());
    } catch (error) {
      _events.add(AgentTurnFailed(error));
      rethrow;
    }
  }
}
