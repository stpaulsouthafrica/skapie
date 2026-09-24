import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_extract.dart';

/// Chat-completions stand-in for models that only answer on `/responses`.
class OpenAiResponsesAgentModel implements AgentModel {
  OpenAiResponsesAgentModel({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.presetId,
    this.headers = const {},
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _client = httpClient ?? http.Client();

  factory OpenAiResponsesAgentModel.fromCompatible(
    OpenAiCompatibleAgentModel source, {
    required String model,
  }) {
    return OpenAiResponsesAgentModel(
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
    final body = responsesAgentBody(
      model: model,
      messages: messages,
      tools: tools,
    );
    _record(tools: tools);
    final sentHeaders = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      ...headers,
    };
    reportAgentHttpRequest(
      url: openaiResponsesUrl(baseUrl),
      headers: sentHeaders,
      body: body,
    );
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(openaiResponsesUrl(baseUrl)),
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
        url: openaiResponsesUrl(baseUrl),
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw AgentHttpException('Unexpected responses body');
    }
    if (decoded['error'] != null) {
      throw AgentHttpException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
        body: response.body,
        url: openaiResponsesUrl(baseUrl),
      );
    }
    return responsesReplyFromBody(decoded);
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
      url: openaiResponsesUrl(baseUrl),
      statusCode: statusCode,
      responseBody: responseBody,
      toolNames: [for (final tool in tools) tool.name],
      reasoningAttached: false,
      surface: 'responses',
    );
  }
}

Map<String, Object?> responsesAgentBody({
  required String model,
  required List<AgentMessage> messages,
  List<AgentTool> tools = const [],
}) {
  String? instructions;
  final input = <Object?>[];
  for (final message in messages) {
    if (message.role == AgentRole.system) {
      instructions = message.content;
      continue;
    }
    if (message.role == AgentRole.tool) {
      input.add({
        'type': 'function_call_output',
        'call_id': message.toolCallId,
        'output': message.content,
      });
      continue;
    }
    final calls = message.toolCalls;
    if (message.role == AgentRole.assistant &&
        calls != null &&
        calls.isNotEmpty) {
      if (message.content.trim().isNotEmpty) {
        input.add({'role': 'assistant', 'content': message.content});
      }
      for (final call in calls) {
        input.add({
          'type': 'function_call',
          'call_id': call.id,
          'name': call.name,
          'arguments': call.argumentsJson,
        });
      }
      continue;
    }
    input.add({
      'role': message.role == AgentRole.assistant ? 'assistant' : 'user',
      'content': message.content,
    });
  }
  return {
    'model': model,
    if (instructions != null && instructions.trim().isNotEmpty)
      'instructions': instructions,
    'input': input,
    if (tools.isNotEmpty)
      'tools': [
        for (final tool in tools)
          {
            'type': 'function',
            'name': tool.name,
            'description': tool.description,
            'parameters': openaiToolParameters(tool.parameters),
          },
      ],
  };
}

AgentModelReply responsesReplyFromBody(Map<dynamic, dynamic> body) {
  final text = extractResponsesOutputText(body);
  final output = body['output'];
  if (output is! List) {
    return AgentModelReply(content: text);
  }
  final calls = <AgentToolCall>[];
  for (final item in output) {
    if (item is! Map || item['type']?.toString() != 'function_call') {
      continue;
    }
    final name = item['name']?.toString() ?? '';
    if (name.isEmpty) {
      continue;
    }
    final arguments = item['arguments'];
    calls.add(
      AgentToolCall(
        id: item['call_id']?.toString() ?? item['id']?.toString() ?? name,
        name: name,
        argumentsJson: arguments is String
            ? arguments
            : jsonEncode(arguments ?? const {}),
      ),
    );
  }
  if (calls.isEmpty) {
    return AgentModelReply(content: text);
  }
  return AgentModelReply(content: text, toolCalls: calls);
}
