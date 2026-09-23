import 'dart:math' as math;
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
  textIn,
  textOut,
  toolOut,
  conversationIn,
  conversationOut,
  repositoryOut,
  toolRepository,
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
      kind == KitPortKind.repositoryOut ||
      kind == KitPortKind.llmConversation ||
      kind == KitPortKind.llmOutput;
}

bool kitPortAccepts(KitPortKind source, KitPortKind target) {
  return switch (source) {
    KitPortKind.textOut =>
      target == KitPortKind.llmInput || target == KitPortKind.llmContext,
    KitPortKind.llmConversation => target == KitPortKind.conversationIn,
    KitPortKind.repositoryOut => target == KitPortKind.toolRepository,
    KitPortKind.toolOut => target == KitPortKind.llmTools,
    KitPortKind.llmOutput =>
      target == KitPortKind.llmInput ||
          target == KitPortKind.llmContext ||
          target == KitPortKind.textIn,
    _ => false,
  };
}

/// Input, Context, and Tools on the left; Conversation and Output on the right.
const int llmRegionCount = 5;

const double llmPortRowHeight = 22;
const double llmPortTop = 4;
const double llmResizeHandle = 10;

/// One row under the title. Repository and LLM labels share it.
const double toolFrameHeight = 64;

/// Header, five port rows, separators, and a resize handle.
/// Status shares the Output row.
const double llmFrameHeight =
    kitBarWorld +
    llmPortTop +
    llmRegionCount * llmPortRowHeight +
    (llmRegionCount - 1) * kitRuleExtent +
    llmResizeHandle +
    8;

/// Vertical center of an LLM port row. Extra frame height spreads the rows.
double llmRegionLabelCenter(double frameHeight, int index) {
  final contentTop = kitBarWorld + llmPortTop;
  final contentBottom = frameHeight - llmResizeHandle - 8;
  final span = math.max(
    contentBottom - contentTop,
    llmRegionCount * llmPortRowHeight + (llmRegionCount - 1) * kitRuleExtent,
  );
  final region = (span - (llmRegionCount - 1) * kitRuleExtent) / llmRegionCount;
  final top = contentTop + index * (region + kitRuleExtent);
  return top + region / 2;
}

/// Play control in the LLM title bar, in world space.
const double llmRunButtonRight = 4;
const double llmRunButtonSlot = 28;

Offset llmRunButtonCenter(SceneObject frame) {
  return Offset(
    frame.x + frame.width - llmRunButtonRight - llmRunButtonSlot / 2,
    frame.y + kitBarWorld / 2,
  );
}

bool llmRunButtonContains(SceneObject frame, Offset world) {
  return Rect.fromCenter(
    center: llmRunButtonCenter(frame),
    width: llmRunButtonSlot,
    height: kitBarWorld,
  ).contains(world);
}

bool llmResizeHandleContains(SceneObject frame, Offset world) {
  final handle = Rect.fromCenter(
    center: Offset(frame.x + frame.width / 2, frame.y + frame.height - 6),
    width: 44,
    height: 16,
  );
  return handle.contains(world);
}

bool llmPortAcceptsMany(KitPortKind kind) {
  return kind == KitPortKind.llmInput ||
      kind == KitPortKind.llmContext ||
      kind == KitPortKind.llmConversation ||
      kind == KitPortKind.llmTools ||
      kind == KitPortKind.llmOutput;
}

bool kitPortsConnect(KitPortKind a, KitPortKind b) {
  if (kitPortIsOutput(a) && !kitPortIsOutput(b)) {
    return kitPortAccepts(a, b);
  }
  if (kitPortIsOutput(b) && !kitPortIsOutput(a)) {
    return kitPortAccepts(b, a);
  }
  return false;
}

Offset textInputCenter(SceneObject frame) {
  return Offset(frame.x, frame.y + frame.height - textOutputInset);
}

Offset textOutputCenter(SceneObject frame) {
  return Offset(
    frame.x + frame.width,
    frame.y + frame.height - textOutputInset,
  );
}

Offset toolPortCenter(SceneObject frame, {required bool right}) {
  return Offset(
    right ? frame.x + frame.width : frame.x,
    frame.y + kitBarWorld + (frame.height - kitBarWorld) / 2,
  );
}

Offset toolOutputCenter(SceneObject frame) =>
    toolPortCenter(frame, right: true);

Offset toolRepositoryCenter(SceneObject frame) =>
    toolPortCenter(frame, right: false);

Offset llmInputCenter(SceneObject frame) => _llmPort(frame, 0, right: false);

Offset llmContextCenter(SceneObject frame) => _llmPort(frame, 1, right: false);

Offset llmToolsCenter(SceneObject frame) => _llmPort(frame, 2, right: false);

Offset llmConversationCenter(SceneObject frame) =>
    _llmPort(frame, 3, right: true);

Offset llmOutputCenter(SceneObject frame) => _llmPort(frame, 4, right: true);

Offset _llmPort(SceneObject frame, int index, {required bool right}) {
  return Offset(
    right ? frame.x + frame.width : frame.x,
    frame.y + llmRegionLabelCenter(frame.height, index),
  );
}

SceneObject _withResize(
  SceneObject frame,
  String? resizeFrameId,
  double? resizeHeight,
) {
  if (resizeFrameId != null &&
      resizeHeight != null &&
      frame.id == resizeFrameId) {
    return frame.copyWith(height: resizeHeight);
  }
  return frame;
}

List<KitPort> kitPorts(
  SceneDocument document, {
  String? resizeFrameId,
  double? resizeHeight,
}) {
  final ports = <KitPort>[];
  for (final listed in document.objects) {
    final object = _withResize(listed, resizeFrameId, resizeHeight);
    if (object.props[skapieRoleProp] != 'frame') {
      continue;
    }
    final kitId = kitIdOf(object);
    if (kitId == boardTextKitId) {
      ports.add(
        KitPort(
          frameId: object.id,
          kind: KitPortKind.textIn,
          center: textInputCenter(object),
          peerId: object.id,
        ),
      );
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
          kind: KitPortKind.conversationIn,
          center: textInputCenter(object),
          peerId: object.id,
        ),
      );
      ports.add(
        KitPort(
          frameId: object.id,
          kind: KitPortKind.conversationOut,
          center: textOutputCenter(object),
          peerId: object.id,
        ),
      );
    } else if (kitId == codingRepositoryKitId) {
      ports.add(
        KitPort(
          frameId: object.id,
          kind: KitPortKind.repositoryOut,
          center: textOutputCenter(object),
          peerId: object.id,
        ),
      );
    } else if (kitId != null && kitId.startsWith('tools.')) {
      if (object.props['requiresRepository'] == true) {
        ports.add(
          KitPort(
            frameId: object.id,
            kind: KitPortKind.toolRepository,
            center: toolRepositoryCenter(object),
            peerId: object.id,
          ),
        );
      }
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

List<SceneCable> sceneCables(
  SceneDocument document, {
  String? resizeFrameId,
  double? resizeHeight,
}) {
  SceneObject h(SceneObject frame) =>
      _withResize(frame, resizeFrameId, resizeHeight);
  final cables = <SceneCable>[];
  for (final frame in repositoryFrames(document)) {
    for (final link in kitLinksOf(frame)) {
      if (link.port != repositoryPort) {
        continue;
      }
      final target = document.objectById(link.to);
      if (target == null || target.props['requiresRepository'] != true) {
        continue;
      }
      cables.add(
        SceneCable(
          id: '${frame.id}|${link.id}',
          ownerId: frame.id,
          port: link.port,
          sourceId: frame.id,
          targetFrameId: target.id,
          from: textOutputCenter(h(frame)),
          to: toolRepositoryCenter(h(target)),
          color: kitAccentColor(target),
          targetBodyId: target.id,
          affectsRun: true,
        ),
      );
    }
  }
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
          from: textOutputCenter(h(frame)),
          to: _llmPortFor(h(target), link.port),
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
          sourceId: target.id,
          targetFrameId: frame.id,
          from: llmConversationCenter(h(target)),
          to: textInputCenter(h(frame)),
          color: kitAccentColor(frame),
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
          from: toolOutputCenter(h(frame)),
          to: llmToolsCenter(h(target)),
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
      if (link.port == llmTextOutPort) {
        final target = document.objectById(link.to);
        if (target == null || kitIdOf(target) != boardTextKitId) {
          continue;
        }
        cables.add(
          SceneCable(
            id: '${body.id}|${link.id}',
            ownerId: body.id,
            port: link.port,
            sourceId: source.id,
            targetFrameId: target.id,
            from: llmOutputCenter(h(source)),
            to: textInputCenter(h(target)),
            color: kitAccentColor(target),
            targetBodyId: link.to,
            affectsRun: false,
          ),
        );
        continue;
      }
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
          from: llmOutputCenter(h(source)),
          to: _llmPortFor(h(target), link.port),
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

List<SceneObject> repositoryFrames(SceneDocument document) {
  return [
    for (final object in document.objects)
      if (object.props[skapieRoleProp] == 'frame' &&
          kitIdOf(object) == codingRepositoryKitId)
        object,
  ];
}

void connectRepositoryToTool({
  required KitApi kitApi,
  required String repositoryFrameId,
  required String toolFrameId,
}) {
  for (final frame in repositoryFrames(kitApi.store.document)) {
    if (frame.id != repositoryFrameId &&
        kitHasLink(frame, to: toolFrameId, port: repositoryPort)) {
      removeKitLink(
        kitApi: kitApi,
        objectId: frame.id,
        to: toolFrameId,
        port: repositoryPort,
      );
    }
  }
  addKitLink(
    kitApi: kitApi,
    objectId: repositoryFrameId,
    to: toolFrameId,
    port: repositoryPort,
  );
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

int llmConnectionCount(
  SceneDocument document,
  String? bodyId,
  KitPortKind kind,
) {
  if (bodyId == null || bodyId.isEmpty) {
    return 0;
  }
  return switch (kind) {
    KitPortKind.llmInput => _linksTo(document, bodyId, llmInputPort),
    KitPortKind.llmContext => _linksTo(document, bodyId, llmContextPort),
    KitPortKind.llmConversation => _linksTo(
      document,
      bodyId,
      llmConversationPort,
    ),
    KitPortKind.llmTools => _linksTo(document, bodyId, llmToolsPort),
    KitPortKind.llmOutput => _outputLinks(document, bodyId),
    _ => 0,
  };
}

/// A run needs a place to write: Output or Conversation.
bool llmRunHasSink(SceneDocument document, String llmBodyId) {
  return llmConnectionCount(document, llmBodyId, KitPortKind.llmOutput) > 0 ||
      llmConnectionCount(document, llmBodyId, KitPortKind.llmConversation) > 0;
}

int _linksTo(SceneDocument document, String bodyId, String port) {
  var count = 0;
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'frame') {
      continue;
    }
    if (kitHasLink(object, to: bodyId, port: port)) {
      count++;
    }
  }
  return count;
}

int _outputLinks(SceneDocument document, String bodyId) {
  var count = 0;
  for (final cable in sceneCables(document)) {
    if (cable.ownerId == bodyId) {
      count++;
    }
  }
  return count;
}

/// Store a cable no matter which end the drag started from.
void connectKitPorts({
  required KitApi kitApi,
  required KitPort from,
  required KitPort to,
}) {
  if (!kitPortsConnect(from.kind, to.kind)) {
    return;
  }
  final output = kitPortIsOutput(from.kind) ? from : to;
  final input = identical(output, from) ? to : from;
  if (output.peerId.isNotEmpty && output.peerId == input.peerId) {
    return;
  }
  switch (output.kind) {
    case KitPortKind.llmConversation:
      addKitLink(
        kitApi: kitApi,
        objectId: input.frameId,
        to: output.peerId,
        port: llmConversationPort,
      );
    case KitPortKind.repositoryOut:
      connectRepositoryToTool(
        kitApi: kitApi,
        repositoryFrameId: output.frameId,
        toolFrameId: input.peerId,
      );
    case KitPortKind.llmOutput:
      connectLlmOutput(
        kitApi: kitApi,
        sourceBodyId: output.peerId,
        targetBodyId: input.peerId,
        port: switch (input.kind) {
          KitPortKind.llmContext => llmContextPort,
          KitPortKind.textIn => llmTextOutPort,
          _ => llmInputPort,
        },
      );
    case KitPortKind.toolOut:
      attachToolKit(
        kitApi: kitApi,
        toolObjectId: output.frameId,
        llmBodyId: input.peerId,
      );
    case KitPortKind.textOut:
      connectTextToLlm(
        kitApi: kitApi,
        textObjectId: output.frameId,
        llmBodyId: input.peerId,
        port: input.kind == KitPortKind.llmContext
            ? llmContextPort
            : llmInputPort,
      );
    default:
      break;
  }
}

/// Shorten text and Conversation kits placed before the two-line preview.
void fitPlacedTextKits(KitApi kitApi) {
  final frames = [
    for (final object in kitApi.store.document.objects)
      if (object.props[skapieRoleProp] == 'frame' &&
          (kitIdOf(object) == boardTextKitId ||
              kitIdOf(object) == harnessConversationKitId) &&
          object.height > textFrameHeight + 0.5)
        object,
  ];
  for (final frame in frames) {
    final bottom = frame.y + textFrameHeight;
    final children = [
      for (final object in kitApi.store.document.objects)
        if (object.id != frame.id && kitChildBelongsToFrame(object, frame))
          object,
    ];
    for (final object in children) {
      if (object.y + object.height <= bottom - 8) {
        continue;
      }
      kitApi.updateFrame(
        id: object.id,
        height: math.max(24, bottom - object.y - 16),
      );
    }
    kitApi.updateFrame(id: frame.id, height: textFrameHeight);
  }
}

/// Shrink LLM kits placed before the compact port card.
void fitPlacedLlmKits(KitApi kitApi) {
  final frames = [
    for (final object in kitApi.store.document.objects)
      if (isLlmKitObject(object) && object.props[skapieRoleProp] == 'frame')
        object,
  ];
  for (final frame in frames) {
    if (frame.height + 0.5 < llmFrameHeight) {
      kitApi.updateFrame(id: frame.id, height: llmFrameHeight);
    }
    final current = kitApi.store.document.objectById(frame.id) ?? frame;
    final body = _llmBody(kitApi.store.document, current);
    final room = current.height - 24;
    if (body != null && body.height + 0.5 < room) {
      kitApi.updateFrame(
        id: body.id,
        x: current.x + 12,
        y: current.y + 12,
        width: current.width - 24,
        height: room,
      );
    }
  }
}

/// Copy this run's visible result into every text kit cabled from Output.
void writeLlmReplyToTextKits({
  required KitApi kitApi,
  required String llmBodyId,
  required String text,
}) {
  final body = kitApi.store.document.objectById(llmBodyId);
  if (body == null) {
    return;
  }
  final document = kitApi.store.document;
  for (final link in kitLinksOf(body)) {
    if (link.port != llmTextOutPort) {
      continue;
    }
    final frame = document.objectById(link.to);
    if (frame == null || kitIdOf(frame) != boardTextKitId) {
      continue;
    }
    final target = textKitBody(document, frame);
    if (target == null) {
      continue;
    }
    kitApi.updateProps(target.id, {'content': text});
  }
}

SceneObject? textKitBody(SceneDocument document, SceneObject frame) {
  for (final object in document.objects) {
    if (object.type != textTypeId) {
      continue;
    }
    if (object.props[skapieRoleProp] == 'frame') {
      continue;
    }
    if (kitChildBelongsToFrame(object, frame)) {
      return object;
    }
  }
  return null;
}

String textKitContent(SceneDocument document, SceneObject frame) {
  return textKitBody(document, frame)?.props['content']?.toString() ?? '';
}

/// First line of a text kit, plus how many lines follow it.
class TextKitSummary {
  const TextKitSummary({required this.firstLine, required this.moreLines});

  final String firstLine;
  final int moreLines;

  String get moreLabel {
    if (moreLines <= 0) {
      return '';
    }
    if (moreLines == 1) {
      return '+1 Line';
    }
    return '+$moreLines Lines';
  }
}

TextKitSummary textKitSummary(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  if (content.isEmpty) {
    return const TextKitSummary(firstLine: '', moreLines: 0);
  }
  return TextKitSummary(firstLine: lines.first, moreLines: lines.length - 1);
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
