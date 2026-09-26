import 'dart:async';

import 'package:skapie/agent/agent_tool.dart';
import 'package:skapie/agent/agent_tool_dispatcher.dart';
import 'package:skapie/agent/run_control.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/world/register.dart';

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

class AgentToolStarted extends AgentEvent {
  const AgentToolStarted(this.call, {this.denial});

  final AgentToolCall call;
  final String? denial;
}

class AgentToolFinished extends AgentEvent {
  const AgentToolFinished(this.call, this.result, {this.denied = false});

  final AgentToolCall call;
  final AgentToolResult result;
  final bool denied;
}

/// The tool was dispatched, but its result was not observed.
class AgentToolUncertain extends AgentEvent {
  const AgentToolUncertain(this.call, this.reason);

  final AgentToolCall call;
  final String reason;
}

class AgentTurnFinished extends AgentEvent {
  const AgentTurnFinished();
}

class AgentTurnFailed extends AgentEvent {
  const AgentTurnFailed(this.error);

  final Object error;
}

/// The caller stopped the turn. No further model or tool work should run.
class AgentRunInterrupted implements Exception {
  const AgentRunInterrupted();
}

/// One conversation. Scene mutations go through [kitApi] tools only.
class AgentSession {
  AgentSession({
    required this.model,
    required this.kitApi,
    String? systemPrompt,
    String? id,
    this.maxToolIterations = defaultMaxToolIterations,
    this.limits = const RunLimits(),
    this.includeTools = true,
    List<AgentTool>? tools,
    List<AgentMessage> history = const [],
  }) : id = id ?? 'agent_${DateTime.now().microsecondsSinceEpoch}',
       _tools = tools ?? createWorldTools(kitApi),
       _messages = [
         AgentMessage(
           role: AgentRole.system,
           content: systemPrompt ?? defaultAgentSystemPrompt,
         ),
         ...history,
       ] {
    _dispatcher = AgentToolDispatcher(_tools);
  }

  final String id;

  final AgentModel model;
  final KitApi kitApi;
  final int maxToolIterations;
  final RunLimits limits;
  final bool includeTools;
  final List<AgentTool> _tools;
  late final AgentToolDispatcher _dispatcher;
  final List<AgentMessage> _messages;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast(sync: true);

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  Stream<AgentEvent> get events => _events.stream;

  /// Append a user message and run the model/tool loop.
  ///
  /// On model failure: user message is kept, [AgentTurnFailed] is emitted,
  /// then the error is rethrown. Tool dispatch errors become tool messages.
  Future<void> sendUser(
    String text, {
    bool Function()? isCancelled,
    Future<void>? cancellation,
    Future<void> Function()? beforeModel,
    Future<String?> Function(String name)? toolDenial,
    Future<void> Function()? afterToolResult,
    Future<void> Function()? beforeToolDispatch,
    Future<void> Function(RunPhase phase, int modelTurns, int toolCalls)?
    onPhase,
    void Function(int outputChars)? onOutput,
  }) async {
    final user = AgentMessage(role: AgentRole.user, content: text);
    _messages.add(user);
    _events.add(const AgentTurnStarted());
    _events.add(AgentMessageAppended(user));
    void stopIfCancelled() {
      if (isCancelled?.call() == true) {
        throw const AgentRunInterrupted();
      }
    }

    final watch = Stopwatch()..start();
    var toolCalls = 0;
    var outputChars = 0;
    final modelLimit = limits.effectiveModelTurns == 0
        ? 0
        : maxToolIterations == 0 ||
              limits.effectiveModelTurns < maxToolIterations
        ? limits.effectiveModelTurns
        : maxToolIterations;
    void checkTime() {
      if (limits.elapsed > Duration.zero && watch.elapsed >= limits.elapsed) {
        throw const RunLimitReached('elapsed time');
      }
    }

    void countOutput(String value) {
      outputChars += value.length;
      onOutput?.call(outputChars);
      if (limits.outputChars > 0 && outputChars > limits.outputChars) {
        throw const RunLimitReached('output volume');
      }
    }

    try {
      for (var i = 0; ; i++) {
        if (modelLimit > 0 && i >= modelLimit) {
          throw const RunLimitReached('model turns');
        }
        stopIfCancelled();
        checkTime();
        await beforeModel?.call();
        stopIfCancelled();
        await onPhase?.call(RunPhase.modelWait, i + 1, toolCalls);
        stopIfCancelled();
        checkTime();
        final request = model.complete(
          messages: List.unmodifiable(_messages),
          tools: includeTools ? List.unmodifiable(_tools) : const <AgentTool>[],
        );
        final reply = await (limits.elapsed == Duration.zero
            ? request
            : request.timeout(
                limits.elapsed - watch.elapsed,
                onTimeout: () => throw const RunLimitReached('elapsed time'),
              ));
        stopIfCancelled();
        checkTime();
        countOutput(reply.content);
        final calls = reply.toolCalls;
        if (calls != null) {
          for (final call in calls) {
            countOutput(call.argumentsJson);
          }
        }
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
          stopIfCancelled();
          checkTime();
          if (limits.toolCalls > 0 && toolCalls >= limits.toolCalls) {
            throw const RunLimitReached('tool calls');
          }
          toolCalls++;
          await onPhase?.call(RunPhase.toolWait, i + 1, toolCalls);
          stopIfCancelled();
          final denial = await toolDenial?.call(call.name);
          stopIfCancelled();
          _events.add(AgentToolStarted(call, denial: denial));
          await beforeToolDispatch?.call();
          stopIfCancelled();
          checkTime();
          final AgentToolResult result;
          if (denial != null) {
            result = AgentToolResult(toolError(denial));
          } else {
            try {
              final dispatch = _dispatcher.dispatch(
                call.name,
                call.argumentsJson,
              );
              final pending = cancellation == null
                  ? dispatch
                  : Future.any<AgentToolResult>([
                      dispatch,
                      cancellation.then<AgentToolResult>(
                        (_) => throw const AgentRunInterrupted(),
                      ),
                    ]);
              result = await (limits.elapsed == Duration.zero
                  ? pending
                  : pending.timeout(
                      limits.elapsed - watch.elapsed,
                      onTimeout: () =>
                          throw const RunLimitReached('elapsed time'),
                    ));
            } on AgentRunInterrupted {
              _events.add(AgentToolUncertain(call, 'Stop or pause requested'));
              await afterToolResult?.call();
              rethrow;
            } on RunLimitReached {
              _events.add(
                AgentToolUncertain(call, 'Elapsed time limit reached'),
              );
              await afterToolResult?.call();
              rethrow;
            }
          }
          _events.add(AgentToolFinished(call, result, denied: denial != null));
          await afterToolResult?.call();
          stopIfCancelled();
          checkTime();
          countOutput(result.content);
          final toolMessage = AgentMessage(
            role: AgentRole.tool,
            content: result.content,
            toolCallId: call.id,
          );
          _messages.add(toolMessage);
          _events.add(AgentMessageAppended(toolMessage));
        }
      }
    } on AgentRunInterrupted {
      rethrow;
    } catch (error) {
      _events.add(AgentTurnFailed(error));
      rethrow;
    }
  }
}
