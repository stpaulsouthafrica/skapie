import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/scene/scene.dart';

/// Selected kit members that can move together. A locked kit stays in place.
List<SceneObject> movableSelectionMembers(
  SceneDocument document,
  Set<String> objectIds,
) {
  final members = <String, SceneObject>{};
  for (final id in objectIds) {
    final object = document.objectById(id);
    if (object == null) continue;
    final kit = kitMembers(document: document, selectedId: id) ?? [object];
    if (kit.any((member) => member.locked)) continue;
    for (final member in kit) {
      members[member.id] = member;
    }
  }
  return members.values.toList();
}

bool moveSelection({
  required SceneStore store,
  required Set<String> objectIds,
  required Offset delta,
}) {
  if (delta == Offset.zero) return false;
  final members = movableSelectionMembers(store.document, objectIds);
  if (members.isEmpty) return false;
  return store.apply(
    SceneBatch([
      for (final member in members)
        UpdateObjectFrame(
          id: member.id,
          x: member.x + delta.dx,
          y: member.y + delta.dy,
        ),
    ]),
  );
}

List<SceneCable> _cables(SceneDocument document) => [
  ...sceneCables(document),
  ...validateBoard(document).extraCables,
];

Map<String, Object?> _linkPatch(List<KitLink> links) => {
  linksProp: [
    for (final link in links)
      {
        'to': link.to,
        'port': link.port,
        if (link.color != null) 'color': link.color,
      },
  ],
  connectedToProp: '',
  connectedPortProp: '',
  attachedToProp: '',
  outputToProp: '',
  outputPortProp: '',
};

/// Remove a mixed selection, its incident links, and tool labels in one undo.
bool deleteSelection({
  required SceneStore store,
  required Set<String> objectIds,
  required Set<String> cableIds,
}) {
  final document = store.document;
  final removeIds = <String>{};
  for (final id in objectIds) {
    final object = document.objectById(id);
    if (object == null) continue;
    for (final member
        in kitMembers(document: document, selectedId: id) ?? [object]) {
      removeIds.add(member.id);
    }
  }

  final cutLinks = <String, Set<String>>{};
  for (final cable in _cables(document)) {
    if (!cableIds.contains(cable.id)) continue;
    final owner = document.objectById(cable.ownerId);
    if (owner == null) continue;
    for (final member
        in kitMembers(document: document, selectedId: owner.id) ?? [owner]) {
      (cutLinks[member.id] ??= {}).add('${cable.targetBodyId}|${cable.port}');
    }
  }

  final ops = <SceneOp>[];
  for (final object in document.objects) {
    if (removeIds.contains(object.id)) continue;
    final before = kitLinksOf(object);
    final after = [
      for (final link in before)
        if (!removeIds.contains(link.to) &&
            !(cutLinks[object.id]?.contains(link.id) ?? false))
          link,
    ];
    if (after.length != before.length) {
      ops.add(UpdateObjectProps(object.id, _linkPatch(after)));
    }
  }
  for (final id in removeIds) {
    ops.add(RemoveObject(id));
  }
  if (ops.isEmpty) return false;

  final changed = SceneBatch(ops).apply(document);
  for (final body in changed.objects) {
    if (!isLlmKitObject(body) || body.props[skapieRoleProp] != 'body') {
      continue;
    }
    final before = llmAttachedToolNames(document, body.id);
    final after = llmAttachedToolNames(changed, body.id);
    if (listEquals(before, after)) continue;
    ops.add(
      UpdateObjectProps(body.id, {
        'content': formatLlmKitContent(
          prompt: body.props['prompt']?.toString() ?? '',
          reply: body.props['reply']?.toString(),
          error: body.props['error']?.toString(),
          model: body.props['model']?.toString(),
          surface: body.props['surface']?.toString(),
          attachedTools: after,
        ),
      }),
    );
  }
  return store.apply(SceneBatch(ops));
}

/// Apply one swatch to selected kits/objects and only the selected cables.
bool colorSelection({
  required SceneStore store,
  required Set<String> objectIds,
  required Set<String> cableIds,
  required Color color,
}) {
  final document = store.document;
  final hex = colorToHex(color);
  final ops = <SceneOp>[];
  final coloredObjects = <String>{};
  for (final id in objectIds) {
    final object = document.objectById(id);
    if (object == null) continue;
    final frame = kitFrameForSelection(document: document, selectedId: id);
    final target = frame ?? object;
    if (!coloredObjects.add(target.id)) continue;
    if (frame != null) {
      ops.add(UpdateObjectProps(frame.id, {kitAccentProp: hex}));
    } else if (object.type == boxTypeId) {
      ops.add(UpdateObjectProps(object.id, {'fill': hex}));
    } else if (object.type == textTypeId) {
      ops.add(UpdateObjectProps(object.id, {'color': hex}));
    }
  }

  final recolorLinks = <String, Set<String>>{};
  for (final cable in _cables(document)) {
    if (!cableIds.contains(cable.id)) continue;
    final owner = document.objectById(cable.ownerId);
    if (owner == null) continue;
    for (final member
        in kitMembers(document: document, selectedId: owner.id) ?? [owner]) {
      (recolorLinks[member.id] ??= {}).add(
        '${cable.targetBodyId}|${cable.port}',
      );
    }
  }
  for (final entry in recolorLinks.entries) {
    final owner = document.objectById(entry.key);
    if (owner == null) continue;
    final links = kitLinksOf(owner);
    if (!links.any((link) => entry.value.contains(link.id))) continue;
    ops.add(
      UpdateObjectProps(
        owner.id,
        _linkPatch([
          for (final link in links)
            entry.value.contains(link.id)
                ? KitLink(to: link.to, port: link.port, color: hex)
                : link,
        ]),
      ),
    );
  }
  if (ops.isEmpty) return false;
  return store.apply(SceneBatch(ops));
}
