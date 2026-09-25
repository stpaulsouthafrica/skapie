import 'dart:convert';

import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/patch_board.dart';
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

class FilteredTool {
  const FilteredTool({required this.name, required this.reason});

  final String name;
  final String reason;

  Map<String, String> toJson() => {'name': name, 'reason': reason};
}

class LlmToolOffer {
  const LlmToolOffer({required this.tools, required this.filtered});

  final List<AgentTool> tools;
  final List<FilteredTool> filtered;

  List<String> get names => [for (final tool in tools) tool.name];

  /// Digest of the schemas actually sent. Not a version number the kits publish.
  String get schemaDigest => toolSchemaDigest(tools);
}

List<AgentTool> worldToolsForLlm({
  required KitApi kitApi,
  required String llmBodyId,
  RepositoryPermission repositoryPermission =
      const SystemRepositoryPermission(),
}) {
  return llmToolOffer(
    kitApi: kitApi,
    llmBodyId: llmBodyId,
    repositoryPermission: repositoryPermission,
  ).tools;
}

LlmToolOffer llmToolOffer({
  required KitApi kitApi,
  required String llmBodyId,
  RepositoryPermission repositoryPermission =
      const SystemRepositoryPermission(),
}) {
  final document = kitApi.store.document;
  final byName = {for (final tool in createWorldTools(kitApi)) tool.name: tool};
  final tools = <AgentTool>[];
  final filtered = <FilteredTool>[];
  final seen = <String>{};
  for (final object in document.objects.toList()) {
    if (!kitLinksOf(object)
        .any((link) => link.to == llmBodyId && link.port == llmToolsPort)) {
      continue;
    }
    if (!isWorldToolKit(object)) {
      filtered.add(
        FilteredTool(name: kitIdOf(object) ?? object.id, reason: 'Wrong type'),
      );
      continue;
    }
    final name = object.props['toolName']?.toString().trim() ?? '';
    if (name.isEmpty) {
      continue;
    }
    if (!seen.add(name)) {
      filtered.add(FilteredTool(name: name, reason: 'Duplicate tool'));
      continue;
    }
    final frame = kitFrameForSelection(
      document: document,
      selectedId: object.id,
    );
    final path = frame == null ? '' : repositoryPathForTool(document, frame.id);
    if ((repositoryToolNames.contains(name) || name == proposePatchToolName) &&
        path.isEmpty) {
      filtered.add(
        FilteredTool(name: name, reason: 'Repository grant missing'),
      );
      continue;
    }
    final tool =
        byName[name] ??
        repositoryToolForName(
          name,
          repositoryPath: path,
          permission: repositoryPermission,
        ) ??
        (name == proposePatchToolName && frame != null
            ? proposePatchTool(
                kitApi: kitApi,
                proposeFrameId: frame.id,
                repositoryPath: path,
                permission: repositoryPermission,
              )
            : null);
    if (tool == null) {
      filtered.add(FilteredTool(name: name, reason: 'Unknown tool'));
      kitApi.updateProps(object.id, {
        'error': 'Unknown tool: $name',
        'content': 'Unknown tool: $name',
      });
      continue;
    }
    tools.add(tool);
  }
  return LlmToolOffer(tools: tools, filtered: filtered);
}

String toolSchemaDigest(List<AgentTool> tools) {
  final canonical = jsonEncode([
    for (final tool in tools)
      {'name': tool.name, 'parameters': tool.parameters ?? const {}},
  ]);
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(canonical)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
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
