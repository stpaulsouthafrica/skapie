import 'dart:convert';

class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.run,
    this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?>? parameters;
  final Future<Map<String, Object?>> Function(Map<String, Object?> args) run;
}

class AgentToolResult {
  const AgentToolResult(this.json);

  final Map<String, Object?> json;

  String get content => jsonEncode(json);
}

Map<String, Object?> toolError(String message) {
  return {'ok': false, 'error': message};
}
