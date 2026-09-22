import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_client.dart';

Map<String, Object?> vanillaCompletionBody({
  required String model,
  required String userText,
  String systemText = '',
  List<ConversationTurn> history = const [],
}) {
  return {
    'model': model,
    'messages': chatMessages(
      userText: userText,
      systemText: systemText,
      history: history,
    ),
  };
}

/// Minimal legal chat completion: one user message, no tools, no system prompt.
class VanillaCompletionClient implements VanillaSurfaceClient {
  VanillaCompletionClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.presetId,
    this.headers = const {},
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _client = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final String? presetId;
  final Map<String, String> headers;
  final Duration timeout;
  final http.Client _client;
  @override
  AgentHttpDiagnostic? lastDiagnostic;

  void _record({int? statusCode, String responseBody = ''}) {
    lastDiagnostic = AgentHttpDiagnostic(
      presetId: presetId,
      baseUrl: openaiNormalizedBaseUrl(baseUrl),
      model: model,
      url: openaiChatCompletionsUrl(baseUrl),
      statusCode: statusCode,
      responseBody: responseBody,
      toolNames: const [],
      reasoningAttached: false,
      surface: 'completions',
    );
  }

  @override
  Future<String> complete({
    required String userText,
    String systemText = '',
    List<ConversationTurn> history = const [],
  }) async {
    final body = vanillaCompletionBody(
      model: model,
      userText: userText,
      systemText: systemText,
      history: history,
    );
    _record();
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
      _record();
      throw AgentHttpException('Request timed out after ${timeout.inSeconds}s');
    }
    _record(statusCode: response.statusCode, responseBody: response.body);
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
    final content = message['content'];
    return content is String ? content : '';
  }
}
