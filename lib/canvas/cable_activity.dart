import 'package:flutter/material.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';

/// Same travel as the connect flash.
const double cableFlashTravelSeconds = 0.32;

/// Kits ease up to a glow, then ease back down. Nothing cuts off.
const double cableGlowInSeconds = 0.28;
const double cableGlowFadeSeconds = 0.48;

/// How long an output write keeps its cable lit before the fade.
const Duration outputActivityHold = Duration(milliseconds: 520);

/// 0 at the start, holds near 1, then eases to 0 once [sinceFade] begins.
double cableGlowEnvelope({
  required double elapsed,
  required double? sinceFade,
}) {
  final fadeInT = (elapsed / cableGlowInSeconds).clamp(0.0, 1.0);
  final fadeIn = fadeInT * fadeInT * (3 - 2 * fadeInT);
  if (sinceFade == null || sinceFade < 0) {
    return fadeIn;
  }
  final fadeOutT = (1 - sinceFade / cableGlowFadeSeconds).clamp(0.0, 1.0);
  final fadeOut = fadeOutT * fadeOutT * (3 - 2 * fadeOutT);
  return fadeIn * fadeOut;
}

/// When a transfer may start fading.
///
/// A one-shot finishes its travel first. A loop finishes the pass already
/// on screen, and always plays at least one full pass.
double activityFadeAt({
  required double born,
  required double now,
  required double cycle,
  required bool finishCycle,
}) {
  if (!finishCycle) {
    final travelEnd = born + cycle;
    return now < travelEnd ? travelEnd : now;
  }
  final elapsed = now - born;
  if (elapsed <= 0) {
    return born + cycle;
  }
  final loops = (elapsed / cycle).ceil();
  return born + loops * cycle;
}

/// Which cable in a tool path is carrying the flash, in order.
int toolFlashIndex({required double elapsed, required int count}) {
  if (count <= 1) {
    return 0;
  }
  final local = elapsed % (count * cableFlashTravelSeconds);
  final index = (local / cableFlashTravelSeconds).floor();
  if (index < 0) {
    return 0;
  }
  if (index >= count) {
    return count - 1;
  }
  return index;
}

/// 0 to 1 travel inside the cable selected by [toolFlashIndex].
double toolFlashTravel({required double elapsed, required int count}) {
  final safeCount = count < 1 ? 1 : count;
  final local = elapsed % (safeCount * cableFlashTravelSeconds);
  final index = toolFlashIndex(elapsed: elapsed, count: safeCount);
  final along = local - index * cableFlashTravelSeconds;
  return (along / cableFlashTravelSeconds).clamp(0.0, 1.0);
}

/// 0 is the cable's [SceneCable.from], 1 is [SceneCable.to].
/// A request travels toward the source (1 → 0). A result travels toward the LLM (0 → 1).
double toolFlashHead({required double travel, required bool towardSource}) {
  final t = travel.clamp(0.0, 1.0);
  final remaining = 1 - t;
  final eased = 1 - remaining * remaining * remaining;
  return towardSource ? 1 - eased : eased;
}

/// Per-frame glow the kit cards read. The cable layer publishes it.
class ActivityGlow extends ChangeNotifier {
  Map<String, double> _levels = const {};

  Map<String, double> get levels => _levels;

  double of(String frameId) => _levels[frameId] ?? 0;

  void publish(Map<String, double> next, {bool notify = true}) {
    if (_levels.length == next.length) {
      var same = true;
      for (final entry in next.entries) {
        final previous = _levels[entry.key];
        if (previous == null || (previous - entry.value).abs() > 0.01) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    _levels = Map<String, double>.unmodifiable(next);
    if (notify) {
      notifyListeners();
    }
  }
}

/// Which transfers are live. The painter turns these into the connect flash.
class CableActivity {
  const CableActivity({
    this.runningBodyId,
    this.seedPorts = const {},
    this.activeToolFrameId,
    this.toolPulse = 0,
    this.toolPulseFrameId,
    this.toolPulseBodyId,
    this.toolResultPulse = 0,
    this.toolResultFrameId,
    this.toolResultBodyId,
    this.writingBodyId,
  });

  static const idle = CableActivity();

  /// LLM body whose run is in flight.
  final String? runningBodyId;

  /// Ports actually read for that run: `input`, `context`, `conversation`.
  final Set<String> seedPorts;

  /// Tool frame executing a call. Cleared when the call finishes.
  final String? activeToolFrameId;

  /// Increments on each tool start so a same-frame finish still animates.
  final int toolPulse;
  final String? toolPulseFrameId;
  final String? toolPulseBodyId;

  /// Increments when a tool kit returns data for the next HTTP request.
  final int toolResultPulse;
  final String? toolResultFrameId;
  final String? toolResultBodyId;

  /// LLM body currently writing its reply onto output cables.
  final String? writingBodyId;

  bool get ticking =>
      runningBodyId != null ||
      activeToolFrameId != null ||
      writingBodyId != null;
}

/// Output and Conversation cables both carry an LLM's reply away from it.
bool cableWritesReply(SceneCable cable, String llmBodyId) {
  return (cable.port == llmTextOutPort && cable.ownerId == llmBodyId) ||
      (cable.port == llmConversationPort && cable.targetBodyId == llmBodyId);
}

/// True when [cable] is carrying [activity] right now.
bool cableCarriesActivity(SceneCable cable, CableActivity activity) {
  final writing = activity.writingBodyId;
  if (writing != null && cableWritesReply(cable, writing)) {
    return true;
  }
  if (_toolCallTouches(
        cable,
        activity.toolResultFrameId,
        activity.toolResultBodyId,
      ) ||
      _toolCallTouches(
        cable,
        activity.activeToolFrameId,
        activity.runningBodyId,
      )) {
    return true;
  }
  final body = activity.runningBodyId;
  if (body != null &&
      activity.seedPorts.contains(cable.port) &&
      cable.targetBodyId == body) {
    return true;
  }
  return false;
}

/// Tool calls travel from the LLM, through the tool kit, into the repository.
/// The result travels back along the same cables.
List<SceneCable> cablesForToolCall({
  required List<SceneCable> cables,
  required String toolFrameId,
  required String llmBodyId,
  bool returning = false,
}) {
  final tools = [
    for (final cable in cables)
      if (cable.port == llmToolsPort &&
          cable.sourceId == toolFrameId &&
          cable.targetBodyId == llmBodyId)
        cable,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final repositories = [
    for (final cable in cables)
      if (cable.port == repositoryPort && cable.targetFrameId == toolFrameId)
        cable,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final members = [...tools, ...repositories];
  if (!returning) {
    return members;
  }
  return members.reversed.toList();
}

/// Request flashes from the LLM toward the tool and repository.
/// A result flash is the opposite direction and uses [toolFlashHead].
bool cableActivityTowardSource(SceneCable cable, CableActivity activity) {
  if (_toolCallTouches(
    cable,
    activity.toolResultFrameId,
    activity.toolResultBodyId,
  )) {
    return false;
  }
  return _toolCallTouches(
    cable,
    activity.activeToolFrameId ?? activity.toolPulseFrameId,
    activity.runningBodyId ?? activity.toolPulseBodyId,
  );
}

bool _toolCallTouches(SceneCable cable, String? tool, String? body) {
  if (tool == null || body == null) {
    return false;
  }
  final toolCable =
      cable.port == llmToolsPort &&
      cable.sourceId == tool &&
      cable.targetBodyId == body;
  final repositoryCable =
      cable.port == repositoryPort && cable.targetFrameId == tool;
  return toolCable || repositoryCable;
}

/// A live cable meets this port, so the port (and its kit) should light.
bool cableTouchesPort(SceneCable cable, KitPort port) {
  return _same(cable.from, port.center) || _same(cable.to, port.center);
}

bool _same(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return dx * dx + dy * dy < 1;
}
