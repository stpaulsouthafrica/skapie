import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
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
  addKitLink(
    kitApi: kitApi,
    objectId: toolObjectId,
    to: llmBodyId,
    port: llmToolsPort,
  );
  refreshLlmToolsChrome(kitApi: kitApi, llmBodyId: llmBodyId);
}

void detachToolKit({
  required KitApi kitApi,
  required String toolObjectId,
  String? llmBodyId,
}) {
  final members =
      kitMembers(document: kitApi.store.document, selectedId: toolObjectId) ??
      [];
  final targets = <String>{
    for (final member in members)
      for (final link in kitLinksOf(member))
        if (link.port == llmToolsPort &&
            (llmBodyId == null || link.to == llmBodyId))
          link.to,
  };
  final before = <KitLink>[];
  for (final member in members) {
    for (final link in kitLinksOf(member)) {
      if (before.any((item) => item.to == link.to && item.port == link.port)) {
        continue;
      }
      before.add(link);
    }
  }
  replaceKitLinks(
    kitApi: kitApi,
    objectId: toolObjectId,
    links: [
      for (final link in before)
        if (!(link.port == llmToolsPort &&
            (llmBodyId == null || link.to == llmBodyId)))
          link,
    ],
  );
  for (final target in targets) {
    if (kitApi.store.document.objectById(target) != null) {
      refreshLlmToolsChrome(kitApi: kitApi, llmBodyId: target);
    }
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
    if (!kitLinksOf(object)
        .any((link) => link.to == llmBodyId && link.port == llmToolsPort)) {
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
