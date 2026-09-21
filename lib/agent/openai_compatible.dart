import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/agent.dart';

class AgentHttpException implements Exception {
  AgentHttpException(this.message);
  final String message;
  @override
  String toString() => message;
}

String openaiNormalizedBaseUrl(String baseUrl) {
  return baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
}

String openaiChatCompletionsUrl(String baseUrl) {
  return '${openaiNormalizedBaseUrl(baseUrl)}/chat/completions';
}

String openaiModelsUrl(String baseUrl) {
  return '${openaiNormalizedBaseUrl(baseUrl)}/models';
}

List<Map<String, Object?>> openaiMessagesFromSession(
  List<AgentMessage> messages,
) {
  return [for (final message in messages) _openaiMessage(message)];
}

List<Map<String, Object?>> openaiToolsFromAgent(List<AgentTool> tools) {
  return [
    for (final tool in tools)
      {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters':
              tool.parameters ??
              const <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              },
        },
      },
  ];
}

AgentModelReply openaiReplyFromMessage(Map<String, Object?> message) {
  final rawCalls = message['tool_calls'];
  final content = message['content'];
  final text = content is String ? content : '';
  if (rawCalls is! List || rawCalls.isEmpty) {
    return AgentModelReply(content: text);
  }
  final calls = <AgentToolCall>[];
  for (final item in rawCalls) {
    if (item is! Map) {
      continue;
    }
    final id = item['id']?.toString() ?? '';
    final function = item['function'];
    if (function is! Map) {
      continue;
    }
    final name = function['name']?.toString() ?? '';
    final arguments = function['arguments'];
    final argumentsJson = arguments is String
        ? arguments
        : jsonEncode(arguments ?? const <String, Object?>{});
    calls.add(AgentToolCall(id: id, name: name, argumentsJson: argumentsJson));
  }
  if (calls.isEmpty) {
    return AgentModelReply(content: text);
  }
  return AgentModelReply(content: text, toolCalls: calls);
}

class OpenAiCompatibleAgentModel implements AgentModel {
  OpenAiCompatibleAgentModel({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.headers = const {},
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.reasoningEffort,
  }) : _client = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final Map<String, String> headers;
  final Duration timeout;
  final String? reasoningEffort;
  final http.Client _client;

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    final effort = reasoningEffort?.trim();
    final body = <String, Object?>{
      'model': model,
      'messages': openaiMessagesFromSession(messages),
      if (tools.isNotEmpty) 'tools': openaiToolsFromAgent(tools),
      if (effort != null && effort.isNotEmpty && effort != 'off')
        'reasoning': {'effort': effort},
    };
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(openaiChatCompletionsUrl(baseUrl)),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AgentHttpException('Request timed out after ${timeout.inSeconds}s');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AgentHttpException('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw AgentHttpException('Unexpected chat completions body');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AgentHttpException('No choices in chat completions response');
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw AgentHttpException('Invalid choice in chat completions response');
    }
    final message = choice['message'];
    if (message is! Map) {
      throw AgentHttpException('Invalid message in chat completions response');
    }
    return openaiReplyFromMessage({
      for (final entry in message.entries) entry.key.toString(): entry.value,
    });
  }
}

Map<String, Object?> _openaiMessage(AgentMessage message) {
  switch (message.role) {
    case AgentRole.system:
      return {'role': 'system', 'content': message.content};
    case AgentRole.user:
      return {'role': 'user', 'content': message.content};
    case AgentRole.assistant:
      return {
        'role': 'assistant',
        'content': message.content,
        if (message.toolCalls != null && message.toolCalls!.isNotEmpty)
          'tool_calls': [
            for (final call in message.toolCalls!)
              {
                'id': call.id,
                'type': 'function',
                'function': {
                  'name': call.name,
                  'arguments': call.argumentsJson,
                },
              },
          ],
      };
    case AgentRole.tool:
      return {
        'role': 'tool',
        'tool_call_id': message.toolCallId ?? '',
        'content': message.content,
      };
  }
}
