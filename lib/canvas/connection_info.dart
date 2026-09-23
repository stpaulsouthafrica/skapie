import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/llm_run_use.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

const int connectionPreviewLimit = 280;

/// What a selected cable is for and what it carries right now.
class ConnectionInfo {
  const ConnectionInfo({
    required this.source,
    required this.destination,
    required this.role,
    required this.value,
    required this.preview,
    this.issue,
  });

  /// `Kit · Port`, or `Deleted kit`.
  final String source;
  final String destination;
  final PortRole role;
  final PortValue value;
  final String preview;

  /// Board problem on this cable, if any.
  final String? issue;

  String get roleLabel => '${role.label} · ${value.label}';
}

ConnectionInfo describeConnection(
  SceneDocument document,
  SceneCable cable, {
  BoardValidation? validation,
}) {
  final checked = validation ?? validateBoard(document);
  final fromKind = cable.fromKind;
  final toKind = cable.toKind;
  final value = fromKind != null
      ? kitPortSpecOf(fromKind).value
      : toKind != null
      ? kitPortSpecOf(toKind).value
      : PortValue.text;
  String issue() {
    final mark = checked.markOf(cable.id);
    if (mark != null) {
      return mark.message;
    }
    for (final item in checked.issues) {
      if (item.cableId == cable.id) {
        return item.message;
      }
    }
    return '';
  }

  final problem = issue();
  return ConnectionInfo(
    source: _end(document, cable.sourceId, fromKind),
    destination: _end(document, cable.targetFrameId, toKind),
    role: value.role,
    value: value,
    preview: _clip(_preview(document, cable, value)),
    issue: problem.isEmpty ? null : problem,
  );
}

String _end(SceneDocument document, String frameId, KitPortKind? kind) {
  final frame = frameId.isEmpty ? null : document.objectById(frameId);
  if (frame == null) {
    return 'Deleted kit';
  }
  final name = kitDisplayName(document, frame);
  return kind == null ? name : '$name · ${kitPortSpecOf(kind).label}';
}

String _clip(String text) {
  final flat = text.trim();
  if (flat.length <= connectionPreviewLimit) {
    return flat;
  }
  return '${flat.substring(0, connectionPreviewLimit - 1)}…';
}

String _preview(SceneDocument document, SceneCable cable, PortValue value) {
  final source = document.objectById(cable.sourceId);
  final target = document.objectById(cable.targetFrameId);
  switch (value) {
    case PortValue.text:
      if (source == null) {
        return '';
      }
      final content = textKitContent(document, source);
      return content.trim().isEmpty ? 'Empty text' : content;
    case PortValue.reply:
      final body = document.objectById(cable.fromPeerId ?? '');
      final reply = body?.props['reply']?.toString() ?? '';
      return reply.trim().isEmpty ? 'No reply yet' : reply;
    case PortValue.conversation:
      final body = target == null ? null : conversationBody(document, target);
      final turns = body == null ? const [] : conversationTurnsOf(body);
      if (turns.isEmpty) {
        return 'No earlier turns yet';
      }
      final count = turns.length == 1 ? '1 turn' : '${turns.length} turns';
      return '$count. Latest: ${turns.last.content}';
    case PortValue.transcript:
      final body = source == null ? null : conversationBody(document, source);
      return body == null
          ? ''
          : formatConversationTranscript(conversationTurnsOf(body));
    case PortValue.tool:
      if (source == null) {
        return '';
      }
      final name = _toolName(document, source);
      final description = source.props['description']?.toString().trim() ?? '';
      return description.isEmpty
          ? 'Offers $name'
          : 'Offers $name: $description';
    case PortValue.repository:
      final path = source?.props[repositoryPathProp]?.toString().trim() ?? '';
      return path.isEmpty
          ? 'No folder chosen. The grant is not live.'
          : 'Read access to $path';
  }
}

String _toolName(SceneDocument document, SceneObject frame) {
  for (final member
      in kitMembers(document: document, selectedId: frame.id) ??
          const <SceneObject>[]) {
    final name = member.props['toolName']?.toString().trim() ?? '';
    if (name.isNotEmpty) {
      return name;
    }
  }
  return kitDisplayName(document, frame);
}

class LastUse {
  const LastUse(this.at, this.how);

  final DateTime at;
  final String how;
}

/// When [cable] carried something in its LLM's latest run, or null.
LastUse? cableLastUse(
  SceneDocument document,
  SceneCable cable,
  Map<String, LlmRunUse> uses,
) {
  final from = cable.fromKind;
  final to = cable.toKind;
  if (to == KitPortKind.llmInput || to == KitPortKind.llmContext) {
    final use = uses[cable.toPeerId];
    final spec = kitPortSpecOf(to!);
    if (use != null && use.readPorts.contains(spec.storedPort)) {
      return LastUse(
        use.startedAt,
        'Read as ${spec.label} when the run started',
      );
    }
    return null;
  }
  if (to == KitPortKind.llmTools) {
    final called = uses[cable.toPeerId]?.toolCalls[cable.sourceId];
    return called == null
        ? null
        : LastUse(called, 'The model called this tool');
  }
  if (to == KitPortKind.toolRepository) {
    DateTime? latest;
    for (final use in uses.values) {
      final called = use.toolCalls[cable.targetFrameId];
      if (called != null && (latest == null || called.isAfter(latest))) {
        latest = called;
      }
    }
    return latest == null
        ? null
        : LastUse(latest, 'The tool read the repository through this grant');
  }
  if (from == KitPortKind.llmOutput) {
    final wrote = uses[cable.fromPeerId]?.wroteOutputAt;
    return wrote == null ? null : LastUse(wrote, 'The reply was written here');
  }
  if (from == KitPortKind.llmConversation) {
    final use = uses[cable.fromPeerId];
    if (use == null) {
      return null;
    }
    final wrote = use.wroteConversationAt;
    if (wrote != null) {
      return LastUse(wrote, 'The exchange was added here');
    }
    return use.readConversation
        ? LastUse(use.startedAt, 'Earlier turns were read')
        : null;
  }
  return null;
}

/// One line for the inspector. Distinguishes "not used" from "no run yet".
String lastUseSummary(
  SceneDocument document,
  SceneCable cable,
  Map<String, LlmRunUse> uses,
) {
  final last = cableLastUse(document, cable, uses);
  if (last != null) {
    return '${_clock(last.at)} · ${last.how}';
  }
  final bodies = <String>{
    for (final (kind, peer) in [
      (cable.fromKind, cable.fromPeerId),
      (cable.toKind, cable.toPeerId),
    ])
      if (kind != null &&
          peer != null &&
          kitPortSpecOf(kind).peer == PortPeer.body)
        peer,
  };
  if (cable.toKind == KitPortKind.toolRepository) {
    for (final item in sceneCables(document)) {
      if (item.toKind == KitPortKind.llmTools &&
          item.sourceId == cable.targetFrameId &&
          item.toPeerId != null) {
        bodies.add(item.toPeerId!);
      }
    }
  }
  return bodies.any(uses.containsKey)
      ? 'Not used in the latest run'
      : 'No run yet this session';
}

String _clock(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = at.toLocal();
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
