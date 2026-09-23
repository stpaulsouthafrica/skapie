import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/repository/repository_tools.dart';

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
  RepositoryPermission repositoryPermission =
      const SystemRepositoryPermission(),
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
    final frame = kitFrameForSelection(
      document: kitApi.store.document,
      selectedId: object.id,
    );
    final tool =
        byName[name] ??
        repositoryToolForName(
          name,
          repositoryPath: frame == null
              ? ''
              : repositoryPathForTool(kitApi.store.document, frame.id),
          permission: repositoryPermission,
        );
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

String repositoryPathForTool(SceneDocument document, String toolFrameId) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'frame' ||
        kitIdOf(object) != codingRepositoryKitId ||
        !kitHasLink(object, to: toolFrameId, port: repositoryPort)) {
      continue;
    }
    return object.props[repositoryPathProp]?.toString().trim() ?? '';
  }
  return '';
}

String? toolFrameIdForName(
  SceneDocument document,
  String llmBodyId,
  String toolName,
) {
  for (final frame in document.objects) {
    if (frame.props[skapieRoleProp] != 'frame' ||
        !isWorldToolKit(frame) ||
        !kitHasLink(frame, to: llmBodyId, port: llmToolsPort)) {
      continue;
    }
    for (final member
        in kitMembers(document: document, selectedId: frame.id) ??
            const <SceneObject>[]) {
      if (member.props['toolName']?.toString() == toolName) {
        return frame.id;
      }
    }
  }
  return null;
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
