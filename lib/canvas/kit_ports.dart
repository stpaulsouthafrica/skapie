import 'dart:ui';

import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

enum KitPortKind { textOut, toolOut, llmInput, llmContext, llmTools, llmOutput }

class KitPort {
  const KitPort({
    required this.frameId,
    required this.kind,
    required this.center,
    required this.peerId,
  });

  final String frameId;
  final KitPortKind kind;
  final Offset center;

  /// Text or tool frame id for an output. LLM body id for an LLM port.
  final String peerId;
}

const double kitPortHitRadius = 10;
const double kitBarWorld = 32;
const double kitBodyInset = 8;
const double kitRuleExtent = 9;
const double kitLabelSize = 11;

/// Text output sits on the right edge, lined up with the bottom Output label.
const double textOutputInset = 18;

bool kitPortIsOutput(KitPortKind kind) {
  return kind == KitPortKind.textOut ||
      kind == KitPortKind.toolOut ||
      kind == KitPortKind.llmOutput;
}

bool kitPortAccepts(KitPortKind source, KitPortKind target) {
  return switch (source) {
    KitPortKind.textOut =>
      target == KitPortKind.llmInput || target == KitPortKind.llmContext,
    KitPortKind.toolOut => target == KitPortKind.llmTools,
    KitPortKind.llmOutput =>
      target == KitPortKind.llmInput || target == KitPortKind.llmContext,
    _ => false,
  };
}

/// Vertical center of an LLM section label, in world units from the frame top.
double llmRegionLabelCenter(double frameHeight, int index) {
  final contentTop = kitBarWorld + kitBodyInset;
  final contentHeight = frameHeight - contentTop - kitBodyInset;
  final region = (contentHeight - 3 * kitRuleExtent) / 4;
  final top = contentTop + index * (region + kitRuleExtent);
  return top + kitLabelSize / 2;
}

Offset textOutputCenter(SceneObject frame) {
  return Offset(
    frame.x + frame.width,
    frame.y + frame.height - textOutputInset,
  );
}

Offset toolOutputCenter(SceneObject frame) {
  return Offset(frame.x + frame.width, frame.y + frame.height / 2);
}

Offset llmInputCenter(SceneObject frame) => _llmPort(frame, 0, right: false);

Offset llmContextCenter(SceneObject frame) => _llmPort(frame, 1, right: false);

Offset llmToolsCenter(SceneObject frame) => _llmPort(frame, 2, right: false);

Offset llmOutputCenter(SceneObject frame) => _llmPort(frame, 3, right: true);

Offset _llmPort(SceneObject frame, int index, {required bool right}) {
  return Offset(
    right ? frame.x + frame.width : frame.x,
    frame.y + llmRegionLabelCenter(frame.height, index),
  );
}

List<KitPort> kitPorts(SceneDocument document) {
  final ports = <KitPort>[];
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'frame') {
      continue;
    }
    final kitId = kitIdOf(object);
    if (kitId == boardTextKitId) {
      ports.add(
        KitPort(
          frameId: object.id,
          kind: KitPortKind.textOut,
          center: textOutputCenter(object),
          peerId: object.id,
        ),
      );
    } else if (kitId != null && kitId.startsWith('tools.')) {
      ports.add(
        KitPort(
          frameId: object.id,
          kind: KitPortKind.toolOut,
          center: toolOutputCenter(object),
          peerId: object.id,
        ),
      );
    } else if (kitId == harnessLlmKitId) {
      final body = _llmBody(document, object);
      if (body == null) {
        continue;
      }
      ports.addAll([
        KitPort(
          frameId: object.id,
          kind: KitPortKind.llmInput,
          center: llmInputCenter(object),
          peerId: body.id,
        ),
        KitPort(
          frameId: object.id,
          kind: KitPortKind.llmContext,
          center: llmContextCenter(object),
          peerId: body.id,
        ),
        KitPort(
          frameId: object.id,
          kind: KitPortKind.llmTools,
          center: llmToolsCenter(object),
          peerId: body.id,
        ),
        KitPort(
          frameId: object.id,
          kind: KitPortKind.llmOutput,
          center: llmOutputCenter(object),
          peerId: body.id,
        ),
      ]);
    }
  }
  return ports;
}

KitPort? hitKitPort(List<KitPort> ports, Offset world) {
  KitPort? best;
  var bestDistance = kitPortHitRadius * kitPortHitRadius;
  for (final port in ports) {
    final delta = port.center - world;
    final distance = delta.dx * delta.dx + delta.dy * delta.dy;
    if (distance <= bestDistance) {
      best = port;
      bestDistance = distance;
    }
  }
  return best;
}

String textConnectedLlmId(SceneObject frame) {
  return frame.props[connectedToProp]?.toString().trim() ?? '';
}

String textConnectedPort(SceneObject frame) {
  final port = frame.props[connectedPortProp]?.toString().trim() ?? '';
  if (port == llmContextPort) {
    return llmContextPort;
  }
  return llmInputPort;
}

void connectTextToLlm({
  required KitApi kitApi,
  required String textObjectId,
  required String llmBodyId,
  String port = llmInputPort,
}) {
  final members =
      kitMembers(document: kitApi.store.document, selectedId: textObjectId) ??
      [];
  for (final member in members) {
    if (kitIdOf(member) != boardTextKitId) {
      continue;
    }
    kitApi.updateProps(member.id, {
      connectedToProp: llmBodyId,
      connectedPortProp: llmBodyId.isEmpty ? '' : port,
    });
  }
}

void disconnectText({required KitApi kitApi, required String textObjectId}) {
  connectTextToLlm(kitApi: kitApi, textObjectId: textObjectId, llmBodyId: '');
}

void connectLlmOutput({
  required KitApi kitApi,
  required String sourceBodyId,
  required String targetBodyId,
  String port = llmInputPort,
}) {
  kitApi.updateProps(sourceBodyId, {
    outputToProp: targetBodyId,
    outputPortProp: targetBodyId.isEmpty ? '' : port,
  });
}

void disconnectLlmOutput({
  required KitApi kitApi,
  required String sourceBodyId,
}) {
  connectLlmOutput(
    kitApi: kitApi,
    sourceBodyId: sourceBodyId,
    targetBodyId: '',
  );
}

List<SceneObject> llmBodies(SceneDocument document) {
  return [
    for (final object in document.objects)
      if (isLlmKitObject(object) && object.props[skapieRoleProp] == 'body')
        object,
  ];
}

List<SceneObject> textFrames(SceneDocument document) {
  return [
    for (final object in document.objects)
      if (object.props[skapieRoleProp] == 'frame' &&
          kitIdOf(object) == boardTextKitId)
        object,
  ];
}

List<SceneObject> toolFrames(SceneDocument document) {
  return [
    for (final object in document.objects)
      if (object.props[skapieRoleProp] == 'frame' && isWorldToolKit(object))
        object,
  ];
}

/// Text cabled into this LLM's Input, otherwise a reply cabled in from another LLM.
String llmCableInput(SceneDocument document, String llmBodyId) {
  if (llmBodyId.isEmpty) {
    return '';
  }
  final texts = <String>[];
  for (final frame in textFrames(document)) {
    if (textConnectedLlmId(frame) != llmBodyId) {
      continue;
    }
    if (textConnectedPort(frame) != llmInputPort) {
      continue;
    }
    final content = textKitContent(document, frame).trim();
    if (content.isNotEmpty) {
      texts.add(content);
    }
  }
  if (texts.isNotEmpty) {
    return texts.join('\n\n');
  }
  final replies = <String>[];
  for (final body in llmBodies(document)) {
    if ((body.props[outputToProp]?.toString().trim() ?? '') != llmBodyId) {
      continue;
    }
    if ((body.props[outputPortProp]?.toString().trim() ?? '') ==
        llmContextPort) {
      continue;
    }
    final reply = body.props['reply']?.toString().trim() ?? '';
    if (reply.isNotEmpty) {
      replies.add(reply);
    }
  }
  return replies.join('\n\n');
}

String textKitContent(SceneDocument document, SceneObject frame) {
  for (final object in document.objects) {
    if (object.type != textTypeId) {
      continue;
    }
    if (object.props[skapieRoleProp] == 'frame') {
      continue;
    }
    if (!kitChildBelongsToFrame(object, frame)) {
      continue;
    }
    return object.props['content']?.toString() ?? '';
  }
  return '';
}

SceneObject? _llmBody(SceneDocument document, SceneObject frame) {
  for (final object in document.objects) {
    if (!isLlmKitObject(object) || object.props[skapieRoleProp] != 'body') {
      continue;
    }
    if (llmBodyBelongsToFrame(object, frame)) {
      return object;
    }
  }
  return null;
}
