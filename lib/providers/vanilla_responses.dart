import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_client.dart';
import 'package:skapie/providers/vanilla_extract.dart';

Map<String, Object?> vanillaResponsesBody({
  required String model,
  required String userText,
}) {
  return {'model': model, 'input': userText};
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
  Future<String> complete({required String userText}) async {
    final body = vanillaResponsesBody(model: model, userText: userText);
    _record();
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(openaiResponsesUrl(baseUrl)),
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
