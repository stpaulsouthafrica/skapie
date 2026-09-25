import 'package:flutter/material.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint_tokens.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

const String registryBoxFill = '#7AA3C7';

/// Ten kit colors. The first is the default champagne accent.
const List<Color> kitSwatches = [
  Color(0xFFC4A46A),
  Color(0xFF7EB6E8),
  Color(0xFF6FBFB0),
  Color(0xFF8FBF7A),
  Color(0xFFE0B15A),
  Color(0xFFD4896A),
  Color(0xFFD47A8A),
  Color(0xFFC49AD4),
  Color(0xFFE8E0D4),
  Color(0xFFB7B7BE),
];

String? kitIdOf(SceneObject object) {
  final id = object.props[skapieKitProp]?.toString().trim() ?? '';
  return id.isEmpty ? null : id;
}

bool isKitObject(SceneObject object) => kitIdOf(object) != null;

/// These kits hide the body widget and draw a two-line preview on the frame.
bool kitUsesTextPreview(String? kitId) {
  return kitId == boardTextKitId ||
      kitId == harnessConversationKitId ||
      kitId == codingPatchProposalKitId ||
      kitId == codingReviewDecisionKitId ||
      kitId == codingApplyPatchKitId ||
      kitId == codingWriteScopeKitId;
}

bool kitChildBelongsToFrame(SceneObject child, SceneObject frame) {
  return child.x >= frame.x - 0.5 &&
      child.y >= frame.y - 0.5 &&
      child.x + child.width <= frame.x + frame.width + 0.5 &&
      child.y + child.height <= frame.y + frame.height + 0.5;
}

double defaultKitCornerRadius(String kitId) => kitRadius;

bool kitHasCustomFill(SceneObject object) {
  final fill = object.props['fill']?.toString().trim() ?? '';
  if (fill.isEmpty) {
    return false;
  }
  if (isKitObject(object) && fill.toUpperCase() == registryBoxFill) {
    return false;
  }
  return true;
}

String colorToHex(Color color) {
  final value = color.toARGB32();
  final hex = (value & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '#${hex.toUpperCase()}';
}

Map<String, Object?> kitAwareProps({
  required String typeId,
  required Map<String, Object?> specProps,
  required Map<String, Object?> defaults,
}) {
  final merged = Map<String, Object?>.of(defaults)..addAll(specProps);
  final kitId = specProps[skapieKitProp]?.toString().trim() ?? '';
  if (kitId.isEmpty) {
    return merged;
  }
  if (typeId == boxTypeId) {
    if (!specProps.containsKey('fill')) {
      merged.remove('fill');
    }
    if (!specProps.containsKey('cornerRadius')) {
      merged['cornerRadius'] = defaultKitCornerRadius(kitId);
    }
  }
  if (typeId == textTypeId && !specProps.containsKey('color')) {
    merged.remove('color');
  }
  return merged;
}

List<SceneObject>? kitMembers({
  required SceneDocument document,
  required String? selectedId,
}) {
  if (selectedId == null) {
    return null;
  }
  final selected = document.objectById(selectedId);
  if (selected == null || !isKitObject(selected)) {
    return null;
  }
  final kitId = kitIdOf(selected)!;
  SceneObject? frame;
  if (selected.props[skapieRoleProp] == 'frame') {
    frame = selected;
  } else {
    for (final object in document.objects) {
      if (kitIdOf(object) != kitId) {
        continue;
      }
      if (object.props[skapieRoleProp] == 'frame' &&
          kitChildBelongsToFrame(selected, object)) {
        frame = object;
        break;
      }
    }
  }
  if (frame == null) {
    return [selected];
  }
  return [
    frame,
    for (final object in document.objects)
      if (object.id != frame.id &&
          kitIdOf(object) == kitId &&
          kitChildBelongsToFrame(object, frame))
        object,
  ];
}

SceneObject? kitFrameForSelection({
  required SceneDocument document,
  required String? selectedId,
}) {
  final members = kitMembers(document: document, selectedId: selectedId);
  if (members == null) {
    return null;
  }
  for (final object in members) {
    if (object.props[skapieRoleProp] == 'frame') {
      return object;
    }
  }
  return members.first;
}

void removeKitSelection({required KitApi kitApi, required String selectedId}) {
  final selected = kitApi.store.document.objectById(selectedId);
  if (selected == null) {
    return;
  }
  final members =
      kitMembers(document: kitApi.store.document, selectedId: selectedId) ??
      [selected];
  final targets = <String>{};
  for (final member in members) {
    final raw = member.props[linksProp];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map && '${item['port']}' == llmToolsPort) {
          final to = item['to']?.toString().trim() ?? '';
          if (to.isNotEmpty) {
            targets.add(to);
          }
        }
      }
      continue;
    }
    final attached = member.props[attachedToProp]?.toString().trim() ?? '';
    if (attached.isNotEmpty) {
      targets.add(attached);
    }
  }
  kitApi.removeObjects([for (final member in members.reversed) member.id]);
  for (final target in targets) {
    if (kitApi.store.document.objectById(target) != null) {
      refreshLlmToolsChrome(kitApi: kitApi, llmBodyId: target);
    }
  }
}

Color kitAccentColor(SceneObject object) {
  return _parseColor(
    object.props[kitAccentProp]?.toString(),
    PaintTokens.champagne,
  );
}

Color kitAccentHairline(Color accent) => accent.withValues(alpha: 0.35);

Color kitFillColor(SceneObject object, PaintTokens tokens) {
  if (isKitObject(object)) {
    return tokens.panel.withValues(alpha: 0.85);
  }
  if (kitHasCustomFill(object)) {
    return _parseColor(object.props['fill']?.toString(), tokens.panel);
  }
  return _parseColor(object.props['fill']?.toString(), const Color(0xFF7AA3C7));
}

double kitCornerRadius(SceneObject object) {
  if (isKitObject(object)) {
    return kitRadius;
  }
  final value = object.props['cornerRadius'];
  if (value is num) {
    return value.toDouble();
  }
  return kitRadius;
}

Color _parseColor(String? value, Color fallback) {
  if (value == null || value.isEmpty) {
    return fallback;
  }
  var hex = value.replaceFirst('#', '');
  if (hex.length == 6) {
    hex = 'FF$hex';
  }
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) {
    return fallback;
  }
  return Color(parsed);
}
