import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/canvas/cable_activity.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

/// Kits and cables an event actually used. Recorded when the event is written.
class RunRoute {
  const RunRoute({this.kits = const [], this.cables = const []});

  final List<String> kits;
  final List<String> cables;

  Map<String, Object?> get fields => {
    if (kits.isNotEmpty) 'kits': kits,
    if (cables.isNotEmpty) 'cables': cables,
  };
}

/// The board highlight for one saved event.
class RunTrace {
  const RunTrace({
    required this.runId,
    required this.sequence,
    required this.kits,
    required this.cables,
    required this.failed,
  });

  final String runId;
  final int sequence;
  final Set<String> kits;
  final Set<String> cables;
  final bool failed;

  /// Every kit and cable the run touched.
  static RunTrace ensemble(RunRecord run) {
    return RunTrace(
      runId: run.id,
      sequence: 0,
      kits: {for (final event in run.events) ...from(run, event).kits},
      cables: {for (final event in run.events) ...from(run, event).cables},
      failed: false,
    );
  }

  static RunTrace from(RunRecord run, RunEvent event) {
    return RunTrace(
      runId: run.id,
      sequence: event.sequence,
      kits: _ids(event.payload['kits']),
      cables: _ids(event.payload['cables']),
      failed:
          event.kind == RunEventKind.runFailed || event.payload['ok'] == false,
    );
  }
}

Set<String> _ids(Object? raw) {
  if (raw is! List) {
    return const {};
  }
  return {
    for (final item in raw)
      if ('$item'.isNotEmpty) '$item',
  };
}

String? _frameId(SceneDocument document, String objectId) {
  return kitFrameForSelection(document: document, selectedId: objectId)?.id;
}

/// Input, context, and conversation cables that fed this model call.
RunRoute routeIntoModel({
  required SceneDocument document,
  required String bodyId,
  required Set<String> ports,
  required bool conversation,
}) {
  final frame = _frameId(document, bodyId);
  final cables = [
    for (final cable in sceneCables(document))
      if (cable.targetBodyId == bodyId &&
          (ports.contains(cable.port) ||
              (conversation && cable.port == llmConversationPort)))
        cable.id,
  ];
  return RunRoute(kits: [if (frame != null) frame], cables: cables);
}

/// The tool kit, the LLM, and the cables that call actually traveled.
RunRoute routeForTool({
  required SceneDocument document,
  required String bodyId,
  required String toolFrameId,
}) {
  final llm = _frameId(document, bodyId);
  final members = cablesForToolCall(
    cables: sceneCables(document),
    toolFrameId: toolFrameId,
    llmBodyId: bodyId,
  );
  return RunRoute(
    kits: [if (llm != null) llm, toolFrameId],
    cables: [for (final cable in members) cable.id],
  );
}

/// Output and conversation cables that carried the reply.
RunRoute routeForReply({
  required SceneDocument document,
  required String bodyId,
}) {
  final frame = _frameId(document, bodyId);
  return RunRoute(
    kits: [if (frame != null) frame],
    cables: [
      for (final cable in sceneCables(document))
        if (cableWritesReply(cable, bodyId)) cable.id,
    ],
  );
}

/// The LLM kit alone. An interrupt has no cable still in motion.
RunRoute routeForKit(SceneDocument document, String bodyId) {
  final frame = _frameId(document, bodyId);
  return RunRoute(kits: [if (frame != null) frame]);
}
