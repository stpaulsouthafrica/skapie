import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_extract.dart';

/// Chat-completions stand-in for models that only answer on `/messages`.
class OpenAiMessagesAgentModel implements AgentModel {
  OpenAiMessagesAgentModel({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.presetId,
    this.headers = const {},
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _client = httpClient ?? http.Client();

  factory OpenAiMessagesAgentModel.fromCompatible(
    OpenAiCompatibleAgentModel source, {
    required String model,
  }) {
    return OpenAiMessagesAgentModel(
      baseUrl: source.baseUrl,
      apiKey: source.apiKey,
      model: model,
      presetId: source.presetId,
      headers: source.headers,
      httpClient: source.httpClient,
      timeout: source.timeout,
    );
  }

  final String baseUrl;
  final String apiKey;
  final String model;
  final String? presetId;
  final Map<String, String> headers;
  final Duration timeout;
  final http.Client _client;
  AgentHttpDiagnostic? lastDiagnostic;

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    final body = messagesAgentBody(
      model: model,
      messages: messages,
      tools: tools,
    );
    _record(tools: tools);
    final sentHeaders = {
      'Authorization': 'Bearer $apiKey',
      'x-api-key': apiKey,
      'Content-Type': 'application/json',
      ...headers,
    };
    reportAgentHttpRequest(
      url: anthropicMessagesUrl(baseUrl),
      headers: sentHeaders,
      body: body,
    );
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(anthropicMessagesUrl(baseUrl)),
            headers: sentHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      _record(tools: tools);
      throw AgentHttpException('Request timed out after ${timeout.inSeconds}s');
    }
    _record(
      tools: tools,
      statusCode: response.statusCode,
      responseBody: response.body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AgentHttpException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
        body: response.body,
        url: anthropicMessagesUrl(baseUrl),
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw AgentHttpException('Unexpected messages body');
    }
    if (decoded['error'] != null) {
      throw AgentHttpException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
        body: response.body,
        url: anthropicMessagesUrl(baseUrl),
      );
    }
    return messagesReplyFromBody(decoded);
  }

  void _record({
    required List<AgentTool> tools,
    int? statusCode,
    String responseBody = '',
  }) {
    lastDiagnostic = AgentHttpDiagnostic(
      presetId: presetId,
      baseUrl: openaiNormalizedBaseUrl(baseUrl),
      model: model,
      url: anthropicMessagesUrl(baseUrl),
      statusCode: statusCode,
      responseBody: responseBody,
      toolNames: [for (final tool in tools) tool.name],
      reasoningAttached: false,
      surface: 'messages',
    );
  }
}

Map<String, Object?> messagesAgentBody({
  required String model,
  required List<AgentMessage> messages,
  List<AgentTool> tools = const [],
}) {
  String? system;
  final thread = <Map<String, Object?>>[];
  for (final message in messages) {
    if (message.role == AgentRole.system) {
      system = message.content;
      continue;
    }
    if (message.role == AgentRole.tool) {
      thread.add({
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': message.toolCallId,
            'content': message.content,
          },
        ],
      });
      continue;
    }
    final calls = message.toolCalls;
    if (message.role == AgentRole.assistant &&
        calls != null &&
        calls.isNotEmpty) {
      thread.add({
        'role': 'assistant',
        'content': [
          if (message.content.trim().isNotEmpty)
            {'type': 'text', 'text': message.content},
          for (final call in calls)
            {
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': _toolInput(call.argumentsJson),
            },
        ],
      });
      continue;
    }
    thread.add({
      'role': message.role == AgentRole.assistant ? 'assistant' : 'user',
      'content': message.content,
    });
  }
  return {
    'model': model,
    'max_tokens': 1024,
    if (system != null && system.trim().isNotEmpty) 'system': system,
    'messages': thread,
    if (tools.isNotEmpty)
      'tools': [
        for (final tool in tools)
          {
            'name': tool.name,
            'description': tool.description,
            'input_schema': openaiToolParameters(tool.parameters),
          },
      ],
  };
}

Object? _toolInput(String argumentsJson) {
  try {
    return jsonDecode(argumentsJson);
  } on FormatException {
    return const <String, Object?>{};
  }
}

AgentModelReply messagesReplyFromBody(Map<dynamic, dynamic> body) {
  final text = extractAnthropicMessageText(body);
  final content = body['content'];
  if (content is! List) {
    return AgentModelReply(content: text);
  }
  final calls = <AgentToolCall>[];
  for (final block in content) {
    if (block is! Map || block['type']?.toString() != 'tool_use') {
      continue;
    }
    final name = block['name']?.toString() ?? '';
    if (name.isEmpty) {
      continue;
    }
    calls.add(
      AgentToolCall(
        id: block['id']?.toString() ?? name,
        name: name,
        argumentsJson: jsonEncode(block['input'] ?? const {}),
      ),
    );
  }
  if (calls.isEmpty) {
    return AgentModelReply(content: text);
  }
  return AgentModelReply(content: text, toolCalls: calls);
}
