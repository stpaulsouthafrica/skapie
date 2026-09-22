import 'dart:ui';

import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

export 'package:skapie/canvas/kit_links.dart';

enum KitPortKind {
  textOut,
  toolOut,
  conversationOut,
  llmInput,
  llmContext,
  llmConversation,
  llmTools,
  llmOutput,
}

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
      kind == KitPortKind.conversationOut ||
      kind == KitPortKind.llmOutput;
}

bool kitPortAccepts(KitPortKind source, KitPortKind target) {
  return switch (source) {
    KitPortKind.textOut =>
      target == KitPortKind.llmInput || target == KitPortKind.llmContext,
    KitPortKind.conversationOut => target == KitPortKind.llmConversation,
    KitPortKind.toolOut => target == KitPortKind.llmTools,
    KitPortKind.llmOutput =>
      target == KitPortKind.llmInput || target == KitPortKind.llmContext,
    _ => false,
  };
}

/// Input, Context, Conversation, Tools, and the Output body.
const int llmRegionCount = 5;

/// Vertical center of an LLM section label, in world units from the frame top.
double llmRegionLabelCenter(double frameHeight, int index) {
  final contentTop = kitBarWorld + kitBodyInset;
  final contentHeight = frameHeight - contentTop - kitBodyInset;
  final rules = llmRegionCount - 1;
  final region = (contentHeight - rules * kitRuleExtent) / llmRegionCount;
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

Offset llmConversationCenter(SceneObject frame) =>
    _llmPort(frame, 2, right: false);

Offset llmToolsCenter(SceneObject frame) => _llmPort(frame, 3, right: false);

Offset llmOutputCenter(SceneObject frame) {
  return Offset(
    frame.x + frame.width,
    frame.y + frame.height - textOutputInset,
  );
}

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
    } else if (kitId == harnessConversationKitId) {
      ports.add(
        KitPort(
          frameId: object.id,
          kind: KitPortKind.conversationOut,
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
          kind: KitPortKind.llmConversation,
          center: llmConversationCenter(object),
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

class SceneCable {
  const SceneCable({
    required this.id,
    required this.ownerId,
    required this.port,
    required this.sourceId,
    required this.targetFrameId,
    required this.from,
    required this.to,
    required this.color,
    required this.targetBodyId,
    required this.affectsRun,
  });

  final String id;
  final String sourceId;
  final String targetFrameId;
  final Offset from;
  final Offset to;
  final Color color;
  final String targetBodyId;

  /// Object that stores the link. Cutting the cable removes it from here.
  final String ownerId;

  /// `input`, `context`, `conversation`, or `tools`.
  final String port;

  /// Input, context, conversation, and tools change the run.
  final bool affectsRun;
}

List<SceneCable> sceneCables(SceneDocument document) {
  final cables = <SceneCable>[];
  for (final frame in textFrames(document)) {
    for (final link in kitLinksOf(frame)) {
      if (link.port != llmInputPort && link.port != llmContextPort) {
        continue;
      }
      final target = kitFrameForSelection(
        document: document,
        selectedId: link.to,
      );
      if (target == null) {
        continue;
      }
      cables.add(
        SceneCable(
          id: '${frame.id}|${link.id}',
          ownerId: frame.id,
          port: link.port,
          sourceId: frame.id,
          targetFrameId: target.id,
          from: textOutputCenter(frame),
          to: _llmPortFor(target, link.port),
          color: kitAccentColor(target),
          targetBodyId: link.to,
          affectsRun: true,
        ),
      );
    }
  }
  for (final frame in conversationFrames(document)) {
    for (final link in kitLinksOf(frame)) {
      if (link.port != llmConversationPort) {
        continue;
      }
      final target = kitFrameForSelection(
        document: document,
        selectedId: link.to,
      );
      if (target == null) {
        continue;
      }
      cables.add(
        SceneCable(
          id: '${frame.id}|${link.id}',
          ownerId: frame.id,
          port: link.port,
          sourceId: frame.id,
          targetFrameId: target.id,
          from: textOutputCenter(frame),
          to: llmConversationCenter(target),
          color: kitAccentColor(target),
          targetBodyId: link.to,
          affectsRun: true,
        ),
      );
    }
  }
  for (final frame in toolFrames(document)) {
    for (final link in kitLinksOf(frame)) {
      if (link.port != llmToolsPort) {
        continue;
      }
      final target = kitFrameForSelection(
        document: document,
        selectedId: link.to,
      );
      if (target == null) {
        continue;
      }
      cables.add(
        SceneCable(
          id: '${frame.id}|${link.id}',
          ownerId: frame.id,
          port: link.port,
          sourceId: frame.id,
          targetFrameId: target.id,
          from: toolOutputCenter(frame),
          to: llmToolsCenter(target),
          color: kitAccentColor(target),
          targetBodyId: link.to,
          affectsRun: true,
        ),
      );
    }
  }
  for (final body in llmBodies(document)) {
    final source = kitFrameForSelection(
      document: document,
      selectedId: body.id,
    );
    if (source == null) {
      continue;
    }
    for (final link in kitLinksOf(body)) {
      if (link.port != llmInputPort && link.port != llmContextPort) {
        continue;
      }
      final target = kitFrameForSelection(
        document: document,
        selectedId: link.to,
      );
      if (target == null) {
        continue;
      }
      cables.add(
        SceneCable(
          id: '${body.id}|${link.id}',
          ownerId: body.id,
          port: link.port,
          sourceId: source.id,
          targetFrameId: target.id,
          from: llmOutputCenter(source),
          to: _llmPortFor(target, link.port),
          color: kitAccentColor(target),
          targetBodyId: link.to,
          affectsRun: true,
        ),
      );
    }
  }
  return cables;
}

Offset _llmPortFor(SceneObject frame, String port) {
  return switch (port) {
    llmContextPort => llmContextCenter(frame),
    llmConversationPort => llmConversationCenter(frame),
    llmToolsPort => llmToolsCenter(frame),
    _ => llmInputCenter(frame),
  };
}

void disconnectSceneCable({required KitApi kitApi, required SceneCable cable}) {
  removeKitLink(
    kitApi: kitApi,
    objectId: cable.ownerId,
    to: cable.targetBodyId,
    port: cable.port,
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

List<SceneObject> conversationFrames(SceneDocument document) {
  return [
    for (final object in document.objects)
      if (object.props[skapieRoleProp] == 'frame' &&
          kitIdOf(object) == harnessConversationKitId)
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
    if (!kitHasLink(frame, to: llmBodyId, port: llmInputPort)) {
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
    if (!kitHasLink(body, to: llmBodyId, port: llmInputPort)) {
      continue;
    }
    final reply = body.props['reply']?.toString().trim() ?? '';
    if (reply.isNotEmpty) {
      replies.add(reply);
    }
  }
  return replies.join('\n\n');
}

/// Text cabled into Context, then an upstream reply cabled into Context.
String llmContextText(SceneDocument document, String llmBodyId) {
  if (llmBodyId.isEmpty) {
    return '';
  }
  final parts = <String>[];
  for (final frame in textFrames(document)) {
    if (!kitHasLink(frame, to: llmBodyId, port: llmContextPort)) {
      continue;
    }
    final content = textKitContent(document, frame).trim();
    if (content.isNotEmpty) {
      parts.add(content);
    }
  }
  for (final body in llmBodies(document)) {
    if (!kitHasLink(body, to: llmBodyId, port: llmContextPort)) {
      continue;
    }
    final reply = body.props['reply']?.toString().trim() ?? '';
    if (reply.isNotEmpty) {
      parts.add(reply);
    }
  }
  return parts.join('\n\n');
}

/// Turns from every Conversation kit cabled into this LLM, in board order.
List<ConversationTurn> llmConversationHistory(
  SceneDocument document,
  String llmBodyId,
) {
  if (llmBodyId.isEmpty) {
    return const [];
  }
  final turns = <ConversationTurn>[];
  for (final frame in conversationFrames(document)) {
    if (!kitHasLink(frame, to: llmBodyId, port: llmConversationPort)) {
      continue;
    }
    final body = conversationBody(document, frame);
    if (body == null) {
      continue;
    }
    turns.addAll(conversationTurnsOf(body));
  }
  return turns;
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
