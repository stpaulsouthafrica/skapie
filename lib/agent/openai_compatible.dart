import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/agent.dart';

class AgentHttpException implements Exception {
  AgentHttpException(this.message, {this.statusCode, this.body, this.url});
  final String message;
  final int? statusCode;
  final String? body;
  final String? url;
  @override
  String toString() => message;
}

/// Set while a run is in flight. Models report the request they are about to send.
void Function(String request)? agentHttpRequestObserver;

/// The HTTP request, with credentials removed.
String redactedHttpRequest({
  required String url,
  required Map<String, String> headers,
  required Object body,
}) {
  final safe = <String, String>{};
  for (final entry in headers.entries) {
    final key = entry.key.toLowerCase();
    final secret = key == 'authorization' || key == 'x-api-key';
    safe[entry.key] = secret ? '[redacted]' : entry.value;
  }
  return jsonEncode({
    'method': 'POST',
    'url': url,
    'headers': safe,
    'body': body,
  });
}

void reportAgentHttpRequest({
  required String url,
  required Map<String, String> headers,
  required Object body,
}) {
  final observer = agentHttpRequestObserver;
  if (observer == null) {
    return;
  }
  observer(redactedHttpRequest(url: url, headers: headers, body: body));
}

class AgentHttpDiagnostic {
  const AgentHttpDiagnostic({
    required this.baseUrl,
    required this.model,
    required this.url,
    this.presetId,
    this.statusCode,
    this.responseBody = '',
    this.toolNames = const [],
    this.reasoningAttached = false,
    this.surface,
  });

  final String? presetId;
  final String baseUrl;
  final String model;
  final String url;
  final int? statusCode;
  final String responseBody;
  final List<String> toolNames;
  final bool reasoningAttached;
  final String? surface;

  String get summary {
    final tools = toolNames.isEmpty
        ? 'tools=off'
        : 'tools=${toolNames.length} (${toolNames.join(', ')})';
    final reason = reasoningAttached ? 'reasoning=on' : 'reasoning=off';
    final status = statusCode == null ? 'no-status' : 'HTTP $statusCode';
    final body = responseBody.length > 400
        ? '${responseBody.substring(0, 400)}...'
        : responseBody;
    return [
      presetId ?? 'http',
      model,
      if (surface != null && surface!.isNotEmpty) surface,
      status,
      tools,
      reason,
      url,
      if (body.isNotEmpty) body,
    ].join(' · ');
  }
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

Map<String, Object?> openaiToolParameters(Map<String, Object?>? parameters) {
  final properties = parameters?['properties'];
  final required = parameters?['required'];
  return {
    'type': 'object',
    'properties': properties is Map
        ? <String, Object?>{
            for (final entry in properties.entries)
              entry.key.toString(): entry.value,
          }
        : <String, Object?>{},
    'additionalProperties': parameters?['additionalProperties'] ?? false,
    if (required is List) 'required': required,
  };
}

List<Map<String, Object?>> openaiToolsFromAgent(List<AgentTool> tools) {
  return [
    for (final tool in tools)
      {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': openaiToolParameters(tool.parameters),
        },
      },
  ];
}

Map<String, Object?> openAiChatCompletionBody({
  required String model,
  required List<Map<String, Object?>> messages,
  List<Map<String, Object?>> tools = const [],
  String? reasoningEffort,
}) {
  final effort = reasoningEffort?.trim();
  final reasoning = effort != null && effort.isNotEmpty && effort != 'off';
  return {
    'model': model,
    'messages': messages,
    if (tools.isNotEmpty) 'tools': tools,
    if (reasoning) 'reasoning': {'effort': effort},
  };
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
    this.presetId,
    this.headers = const {},
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.reasoningEffort,
  }) : _client = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final String? presetId;
  final Map<String, String> headers;
  final Duration timeout;
  final String? reasoningEffort;
  final http.Client _client;
  http.Client get httpClient => _client;
  AgentHttpDiagnostic? lastDiagnostic;

  /// Same endpoint and key, with the kit's chosen model id.
  OpenAiCompatibleAgentModel withModel(String model) {
    if (model == this.model) {
      return this;
    }
    return OpenAiCompatibleAgentModel(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      presetId: presetId,
      headers: headers,
      httpClient: _client,
      timeout: timeout,
      reasoningEffort: reasoningEffort,
    );
  }

  bool get _reasoningAttached {
    final effort = reasoningEffort?.trim();
    return effort != null && effort.isNotEmpty && effort != 'off';
  }

  void _recordDiagnostic({
    required List<AgentTool> tools,
    int? statusCode,
    String responseBody = '',
  }) {
    lastDiagnostic = AgentHttpDiagnostic(
      presetId: presetId,
      baseUrl: openaiNormalizedBaseUrl(baseUrl),
      model: model,
      url: openaiChatCompletionsUrl(baseUrl),
      statusCode: statusCode,
      responseBody: responseBody,
      toolNames: [for (final tool in tools) tool.name],
      reasoningAttached: _reasoningAttached,
      surface: 'completions',
    );
  }

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    final body = openAiChatCompletionBody(
      model: model,
      messages: openaiMessagesFromSession(messages),
      tools: tools.isEmpty ? const [] : openaiToolsFromAgent(tools),
      reasoningEffort: _reasoningAttached ? reasoningEffort : null,
    );
    _recordDiagnostic(tools: tools);
    final sentHeaders = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      ...headers,
    };
    reportAgentHttpRequest(
      url: openaiChatCompletionsUrl(baseUrl),
      headers: sentHeaders,
      body: body,
    );
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(openaiChatCompletionsUrl(baseUrl)),
            headers: sentHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      _recordDiagnostic(tools: tools);
      throw AgentHttpException('Request timed out after ${timeout.inSeconds}s');
    }
    _recordDiagnostic(
      tools: tools,
      statusCode: response.statusCode,
      responseBody: response.body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AgentHttpException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
        body: response.body,
        url: openaiChatCompletionsUrl(baseUrl),
      );
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
