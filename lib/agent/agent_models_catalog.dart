import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/model_surface.dart';

class AgentModelInfo {
  const AgentModelInfo({
    required this.id,
    required this.displayName,
    this.thinkingLevels = const [],
    this.surface,
    this.selectable = true,
    this.subtitle,
  });

  final String id;
  final String displayName;
  final List<String> thinkingLevels;
  final ModelSurface? surface;
  final bool selectable;
  final String? subtitle;
}

List<AgentModelInfo> parseAgentModelsCatalog(Object? decoded) {
  if (decoded is! Map) {
    throw AgentHttpException('Unexpected models body');
  }
  final data = decoded['data'];
  if (data is! List) {
    throw AgentHttpException('No data in models response');
  }
  final seen = <String>{};
  final models = <AgentModelInfo>[];
  for (final item in data) {
    if (item is! Map) {
      continue;
    }
    final id = item['id']?.toString().trim() ?? '';
    if (id.isEmpty || seen.contains(id)) {
      continue;
    }
    seen.add(id);
    final name = item['name']?.toString().trim();
    models.add(
      AgentModelInfo(
        id: id,
        displayName: (name == null || name.isEmpty) ? id : name,
        thinkingLevels: _thinkingLevels(item),
      ),
    );
  }
  return models;
}

Future<List<AgentModelInfo>> fetchAgentModels({
  required String baseUrl,
  required String apiKey,
  Map<String, String> headers = const {},
  http.Client? httpClient,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final client = httpClient ?? http.Client();
  final http.Response response;
  try {
    response = await client
        .get(
          Uri.parse(openaiModelsUrl(baseUrl)),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            ...headers,
          },
        )
        .timeout(timeout);
  } on TimeoutException {
    throw AgentHttpException('Request timed out after ${timeout.inSeconds}s');
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw AgentHttpException('HTTP ${response.statusCode}: ${response.body}');
  }
  final decoded = jsonDecode(response.body);
  return parseAgentModelsCatalog(decoded);
}

List<String> _thinkingLevels(Map<dynamic, dynamic> item) {
  final fromSupported = _stringList(item['supported_efforts']);
  if (fromSupported.isNotEmpty) {
    return fromSupported;
  }
  final reasoning = item['reasoning'];
  if (reasoning is List) {
    return _stringList(reasoning);
  }
  if (reasoning is Map) {
    return _stringList(
      reasoning['efforts'] ??
          reasoning['supported_efforts'] ??
          reasoning['effort'],
    );
  }
  return const [];
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  final levels = <String>[];
  final seen = <String>{};
  for (final item in value) {
    final text = item?.toString().trim() ?? '';
    if (text.isEmpty || seen.contains(text)) {
      continue;
    }
    seen.add(text);
    levels.add(text);
  }
  return levels;
}
