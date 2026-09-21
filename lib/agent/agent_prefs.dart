import 'dart:convert';
import 'dart:io';

const String agentPrefsFileName = 'agent_prefs.json';
const String appSupportAgentSubdir = 'skapie';

class AgentPrefs {
  const AgentPrefs({
    required this.providerId,
    this.model,
    this.thinkingLevel,
    this.baseUrl,
    this.apiKey,
  });

  final String providerId;
  final String? model;
  final String? thinkingLevel;
  final String? baseUrl;
  final String? apiKey;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 2,
      'provider': providerId,
      if (model != null && model!.trim().isNotEmpty) 'model': model,
      if (thinkingLevel != null &&
          thinkingLevel!.trim().isNotEmpty &&
          thinkingLevel != 'off')
        'thinkingLevel': thinkingLevel,
      if (apiKey != null && apiKey!.trim().isNotEmpty) 'apiKey': apiKey,
    };
  }

  factory AgentPrefs.fromJson(Map<dynamic, dynamic> json) {
    String? trim(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return AgentPrefs(
      providerId: trim(json['provider']) ?? 'fake',
      model: trim(json['model']),
      thinkingLevel: trim(json['thinkingLevel']),
      baseUrl: trim(json['baseUrl']),
      apiKey: trim(json['apiKey']),
    );
  }
}

File agentPrefsFile(Directory appSupportDirectory) {
  return File(
    '${appSupportDirectory.path}/$appSupportAgentSubdir/$agentPrefsFileName',
  );
}

class AgentPrefsStore {
  AgentPrefsStore(this.file);

  final File file;

  Future<AgentPrefs?> load() async {
    if (!file.existsSync()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return AgentPrefs.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> save(AgentPrefs prefs) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(prefs.toJson()),
    );
  }
}
