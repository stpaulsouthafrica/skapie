import 'dart:convert';

import 'package:skapie/agent/agent_tool.dart';

class AgentToolDispatcher {
  AgentToolDispatcher(List<AgentTool> tools)
    : _byName = {for (final tool in tools) tool.name: tool};

  final Map<String, AgentTool> _byName;

  Future<AgentToolResult> dispatch(String name, String argumentsJson) async {
    final tool = _byName[name];
    if (tool == null) {
      return AgentToolResult(toolError('Unknown tool: $name'));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(argumentsJson);
    } catch (error) {
      return AgentToolResult(toolError('Invalid JSON args: $error'));
    }
    if (decoded is! Map) {
      return AgentToolResult(toolError('Args must be a JSON object'));
    }
    final args = <String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    };
    try {
      return AgentToolResult(await tool.run(args));
    } catch (error) {
      return AgentToolResult(toolError('$error'));
    }
  }
}
