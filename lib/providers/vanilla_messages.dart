import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_client.dart';
import 'package:skapie/providers/vanilla_extract.dart';

Map<String, Object?> vanillaMessagesBody({
  required String model,
  required String userText,
  String systemText = '',
  List<ConversationTurn> history = const [],
}) {
  final system = systemText.trim();
  final messages = chatMessages(userText: userText, history: history);
  return {
    'model': model,
    'max_tokens': 1024,
    if (system.isNotEmpty) 'system': system,
    'messages': [
      for (final message in messages)
        if (message['role'] != 'system') message,
    ],
  };
}

class VanillaMessagesClient implements VanillaSurfaceClient {
  VanillaMessagesClient({
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
      url: anthropicMessagesUrl(baseUrl),
      statusCode: statusCode,
      responseBody: responseBody,
      toolNames: const [],
      reasoningAttached: false,
      surface: 'messages',
    );
  }

  @override
  Future<String> complete({
    required String userText,
    String systemText = '',
    List<ConversationTurn> history = const [],
  }) async {
    final body = vanillaMessagesBody(
      model: model,
      userText: userText,
      systemText: systemText,
      history: history,
    );
    _record();
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
      _record();
      throw AgentHttpException('Request timed out after ${timeout.inSeconds}s');
    }
    _record(statusCode: response.statusCode, responseBody: response.body);
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
    return extractAnthropicMessageText(decoded);
  }
}
