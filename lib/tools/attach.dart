import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

bool isWorldToolKit(SceneObject object) {
  final id = object.props[skapieKitProp]?.toString() ?? '';
  return id.startsWith('tools.');
}

String? worldToolKitIdOf(SceneObject object) {
  final id = object.props[skapieKitProp]?.toString() ?? '';
  return id.startsWith('tools.') ? id : null;
}

void attachToolKit({
  required KitApi kitApi,
  required String toolObjectId,
  required String llmBodyId,
}) {
  final selected = kitApi.store.document.objectById(toolObjectId);
  if (selected == null) {
    return;
  }
  final kitId = worldToolKitIdOf(selected);
  if (kitId == null) {
    return;
  }
  for (final object in kitApi.store.document.objects.toList()) {
    if (object.props[skapieKitProp] == kitId) {
      kitApi.updateProps(object.id, {attachedToProp: llmBodyId});
    }
  }
  refreshLlmToolsChrome(kitApi: kitApi, llmBodyId: llmBodyId);
}

void detachToolKit({required KitApi kitApi, required String toolObjectId}) {
  final selected = kitApi.store.document.objectById(toolObjectId);
  if (selected == null) {
    return;
  }
  final kitId = worldToolKitIdOf(selected);
  if (kitId == null) {
    return;
  }
  final previous = selected.props[attachedToProp]?.toString() ?? '';
  for (final object in kitApi.store.document.objects.toList()) {
    if (object.props[skapieKitProp] == kitId) {
      kitApi.updateProps(object.id, {attachedToProp: ''});
    }
  }
  if (previous.isNotEmpty) {
    refreshLlmToolsChrome(kitApi: kitApi, llmBodyId: previous);
  }
}

List<String> attachedToolNames({
  required KitApi kitApi,
  required String llmBodyId,
}) {
  return llmAttachedToolNames(kitApi.store.document, llmBodyId);
}

List<AgentTool> worldToolsForLlm({
  required KitApi kitApi,
  required String llmBodyId,
}) {
  final byName = {for (final tool in createWorldTools(kitApi)) tool.name: tool};
  final tools = <AgentTool>[];
  for (final object in kitApi.store.document.objects.toList()) {
    if (!isWorldToolKit(object)) {
      continue;
    }
    if (object.props[attachedToProp]?.toString() != llmBodyId) {
      continue;
    }
    final name = object.props['toolName']?.toString().trim() ?? '';
    if (name.isEmpty) {
      continue;
    }
    final tool = byName[name];
    if (tool == null) {
      kitApi.updateProps(object.id, {
        'error': 'Unknown tool: $name',
        'content': 'Unknown tool: $name',
      });
      continue;
    }
    if (!tools.any((item) => item.name == name)) {
      tools.add(tool);
    }
  }
  return tools;
}

void refreshLlmToolsChrome({
  required KitApi kitApi,
  required String llmBodyId,
}) {
  final body = kitApi.store.document.objectById(llmBodyId);
  if (body == null || !isLlmKitObject(body)) {
    return;
  }
  kitApi.updateProps(llmBodyId, {
    'content': formatLlmKitContent(
      prompt: body.props['prompt']?.toString() ?? '',
      reply: body.props['reply']?.toString(),
      error: body.props['error']?.toString(),
      model: body.props['model']?.toString(),
      surface: body.props['surface']?.toString(),
      attachedTools: attachedToolNames(kitApi: kitApi, llmBodyId: llmBodyId),
    ),
  });
}
