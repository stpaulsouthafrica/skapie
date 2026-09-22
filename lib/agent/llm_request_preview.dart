import 'dart:convert';

import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/model_surface.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';
import 'package:skapie/providers/vanilla_completion.dart';
import 'package:skapie/providers/vanilla_extract.dart';
import 'package:skapie/providers/vanilla_messages.dart';
import 'package:skapie/providers/vanilla_responses.dart';

const _encoder = JsonEncoder.withIndent('  ');

/// The HTTP call [AgentController.sendUser] will make for this kit, before Run.
String formatLlmRequestPreview({
  required String prompt,
  String systemText = '',
  List<ConversationTurn> history = const [],
  required bool useFake,
  required AgentModel sessionModel,
  required List<AgentTool> attachedTools,
  required String presetId,
  required String? baseUrl,
  required String? apiKey,
  required String? runtimeModel,
  required String kitModel,
  required String kitProvider,
  required String sessionId,
}) {
  final pending = prompt.trim().isEmpty
      ? 'Run does not send until Input has text.\n\n'
      : '';
  if (attachedTools.isNotEmpty) {
    if (useFake || sessionModel is FakeAgentModel) {
      return '$pending${_fake(prompt, systemText: systemText, history: history, tools: attachedTools)}';
    }
    if (sessionModel is OpenAiCompatibleAgentModel) {
      final body = openAiChatCompletionBody(
        model: sessionModel.model,
        messages: openaiMessagesFromSession([
          AgentMessage(role: AgentRole.system, content: systemText),
          for (final turn in history)
            AgentMessage(
              role: turn.role == 'assistant'
                  ? AgentRole.assistant
                  : AgentRole.user,
              content: turn.content,
            ),
          AgentMessage(role: AgentRole.user, content: prompt),
        ]),
        tools: openaiToolsFromAgent(attachedTools),
        reasoningEffort: sessionModel.reasoningEffort,
      );
      return '$pending${_http(url: openaiChatCompletionsUrl(sessionModel.baseUrl), headers: {'Authorization': 'Bearer ${sessionModel.apiKey}', 'Content-Type': 'application/json', ...sessionModel.headers}, body: body, apiKey: sessionModel.apiKey)}';
    }
    return '${pending}No HTTP preview for this model.';
  }
  if (useFake) {
    return '$pending${_fake(prompt, systemText: systemText, history: history)}';
  }
  final model = kitModel.trim().isNotEmpty
      ? kitModel.trim()
      : (runtimeModel?.trim() ?? '');
  final provider = kitProvider.trim().isNotEmpty
      ? kitProvider.trim()
      : presetId;
  if (baseUrl == null ||
      baseUrl.trim().isEmpty ||
      apiKey == null ||
      apiKey.isEmpty ||
      model.isEmpty) {
    return '${pending}No request. Connect a provider and choose a model.';
  }
  final surface = _surface(provider: provider, model: model);
  if (surface == null) {
    return '$pending'
        'No request is sent.\n'
        'Model "$model" is not in the Skapie catalog yet.';
  }
  final headers = <String, String>{
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    if (surface == ModelSurface.messages) 'x-api-key': apiKey,
    ...agentProviderHeaders(presetId: provider, sessionId: sessionId),
  };
  final url = switch (surface) {
    ModelSurface.completions => openaiChatCompletionsUrl(baseUrl),
    ModelSurface.responses => openaiResponsesUrl(baseUrl),
    ModelSurface.messages => anthropicMessagesUrl(baseUrl),
  };
  final body = switch (surface) {
    ModelSurface.completions => vanillaCompletionBody(
      model: model,
      userText: prompt,
      systemText: systemText,
      history: history,
    ),
    ModelSurface.responses => vanillaResponsesBody(
      model: model,
      userText: prompt,
      systemText: systemText,
      history: history,
    ),
    ModelSurface.messages => vanillaMessagesBody(
      model: model,
      userText: prompt,
      systemText: systemText,
      history: history,
    ),
  };
  return '$pending${_http(url: url, headers: headers, body: body, apiKey: apiKey)}';
}

ModelSurface? _surface({required String provider, required String model}) {
  if (provider != 'opencode-go') {
    return ModelSurface.completions;
  }
  final entry = lookupOpenCodeGoModel(model);
  if (entry == null || !entry.show || !entry.vanillaOk) {
    return null;
  }
  return entry.surface;
}

String _fake(
  String prompt, {
  String systemText = '',
  List<ConversationTurn> history = const [],
  List<AgentTool> tools = const [],
}) {
  final buffer = StringBuffer('No network request. Fake echo.');
  final system = systemText.trim();
  if (system.isNotEmpty) {
    buffer.write('\n\nsystem:\n$system');
  }
  for (final turn in history) {
    buffer.write('\n\n${turn.role}:\n${turn.content}');
  }
  buffer.write('\n\nuser:\n$prompt');
  if (tools.isNotEmpty) {
    buffer.write('\n\ntools:\n');
    for (final tool in tools) {
      buffer.write('${tool.name}\n');
    }
  }
  return buffer.toString().trimRight();
}

String _http({
  required String url,
  required Map<String, String> headers,
  required Map<String, Object?> body,
  required String apiKey,
}) {
  final lines = <String>['POST $url', ''];
  for (final entry in headers.entries) {
    lines.add('${entry.key}: ${_redact(entry.key, entry.value, apiKey)}');
  }
  lines.add('');
  lines.add(_encoder.convert(body));
  return lines.join('\n');
}

String _redact(String name, String value, String apiKey) {
  final lower = name.toLowerCase();
  if (lower == 'authorization' || lower == 'x-api-key') {
    return '<redacted>';
  }
  if (apiKey.isNotEmpty && value.contains(apiKey)) {
    return value.replaceAll(apiKey, '<redacted>');
  }
  return value;
}
