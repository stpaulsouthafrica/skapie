import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_client.dart';
import 'package:skapie/providers/vanilla_extract.dart';

Map<String, Object?> vanillaResponsesBody({
  required String model,
  required String userText,
  String systemText = '',
  List<ConversationTurn> history = const [],
}) {
  final system = systemText.trim();
  if (system.isEmpty && history.isEmpty) {
    return {'model': model, 'input': userText};
  }
  return {
    'model': model,
    if (system.isNotEmpty) 'instructions': system,
    'input': chatMessages(
      userText: userText,
      history: history,
    ).where((message) => message['role'] != 'system').toList(),
  };
}

class VanillaResponsesClient implements VanillaSurfaceClient {
  VanillaResponsesClient({
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
      url: openaiResponsesUrl(baseUrl),
      statusCode: statusCode,
      responseBody: responseBody,
      toolNames: const [],
      reasoningAttached: false,
      surface: 'responses',
    );
  }

  @override
  Future<String> complete({
    required String userText,
    String systemText = '',
    List<ConversationTurn> history = const [],
  }) async {
    final body = vanillaResponsesBody(
      model: model,
      userText: userText,
      systemText: systemText,
      history: history,
    );
    _record();
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
      _record();
      throw AgentHttpException('Request timed out after ${timeout.inSeconds}s');
    }
    _record(statusCode: response.statusCode, responseBody: response.body);
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
    return extractResponsesOutputText(decoded);
  }
}
