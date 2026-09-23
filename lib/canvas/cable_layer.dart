import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/cable_activity.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/cables/cable_hit.dart';
import 'package:skapie/paint/cables/cable_motion.dart';
import 'package:skapie/paint/cables/cable_painter.dart';
import 'package:skapie/scene/scene.dart';

const double _travelSeconds = cableFlashTravelSeconds;
const double _settleSeconds = 0.52;
const double _fadeSeconds = cableGlowFadeSeconds;

/// How a cable that just appeared should be drawn.
///
/// A drag already showed the whole stroke, so the flash leaves from the
/// port the pointer started on. A cable that was not dragged grows out of
/// the output.
class ConnectArrival {
  const ConnectArrival({required this.grow, required this.towardSource});

  /// The stroke reveals from the output. False when a drag already drew it.
  final bool grow;

  /// The flash runs from the input back toward the output.
  final bool towardSource;

  double draw(double eased) => grow ? eased.clamp(0.0, 1.0) : 1;

  double flash(double eased) {
    final t = eased.clamp(0.0, 1.0);
    return towardSource ? 1 - t : t;
  }
}

/// [dragFrameId] is the frame the pointer started on, kept from the drag
/// that ended as this cable was stored.
ConnectArrival connectArrival({
  required bool sawDrag,
  required String? dragFrameId,
  required String sourceId,
  required String targetFrameId,
}) {
  final fromSource = sawDrag && dragFrameId != null && dragFrameId == sourceId;
  final fromTarget =
      sawDrag &&
      dragFrameId != null &&
      dragFrameId == targetFrameId &&
      dragFrameId != sourceId;
  if (fromTarget) {
    return const ConnectArrival(grow: false, towardSource: true);
  }
  if (fromSource) {
    return const ConnectArrival(grow: false, towardSource: false);
  }
  return const ConnectArrival(grow: true, towardSource: false);
}

class CableLayer extends StatefulWidget {
  const CableLayer({
    super.key,
    required this.camera,
    required this.viewportSize,
    required this.document,
    this.previewDelta = Offset.zero,
    this.previewIds = const {},
    this.dragFrameId,
    this.dragKind,
    this.dragCursor,
    this.resizeFrameId,
    this.resizeHeight,
    this.previewOnly = false,
    this.paintDrag = true,
    this.activity = CableActivity.idle,
    this.glow,
    this.motion,
    this.retractions = const [],
    this.onRetractionDone,
    this.validation = BoardValidation.empty,
    this.invalidColor = const Color(0xFFB85C5C),
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final SceneDocument document;
  final Offset previewDelta;
  final Set<String> previewIds;
  final String? dragFrameId;
  final KitPortKind? dragKind;
  final Offset? dragCursor;
  final String? resizeFrameId;
  final double? resizeHeight;
  final bool previewOnly;
  final bool paintDrag;
  final CableActivity activity;
  final ActivityGlow? glow;
  final CableMotion? motion;
  final List<RetractingCable> retractions;
  final ValueChanged<RetractingCable>? onRetractionDone;

  /// Marked cables are drawn dashed in [invalidColor], never as live.
  final BoardValidation validation;
  final Color invalidColor;

  @override
  State<CableLayer> createState() => _CableLayerState();
}

class _CableLayerState extends State<CableLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _watch = Stopwatch();
  var _primed = false;
  var _known = <String>{};
  final _arrivals = <String, _Arrival>{};
  var _sawDrag = false;
  String? _dragSource;
  final _acts = <String, _Act>{};
  final _fading = <_Act>[];
  var _seenToolPulse = 0;
  var _seenToolResultPulse = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!mounted) {
        return;
      }
      final cables = sceneCables(
        widget.document,
        resizeFrameId: widget.resizeFrameId,
        resizeHeight: widget.resizeHeight,
      );
      _pushMotion(cables);
      _syncActs(cables);
      _publishGlow(notify: true);
      final finished = [
        for (final item in widget.retractions)
          if (item.progress >= 1) item,
      ];
      setState(() {});
      for (final item in finished) {
        widget.onRetractionDone?.call(item);
      }
    });
    _watch.start();
  }

  double get _clock => _watch.elapsedMicroseconds / 1000000;

  @override
  void dispose() {
    _ticker.dispose();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.previewOnly
        ? const <SceneCable>[]
        : sceneCables(
            widget.document,
            resizeFrameId: widget.resizeFrameId,
            resizeHeight: widget.resizeHeight,
          );
    if (!widget.previewOnly) {
      _note(scene);
      _syncActs(scene);
      _publishGlow(notify: false);
    }
    final painted = <PaintedCable>[
      for (final cable in scene) _paintOf(cable),
      if (!widget.previewOnly)
        for (final cable in widget.validation.extraCables) _paintOf(cable),
      ..._retracts(),
      ..._drag(),
    ];
    return IgnorePointer(
      child: CustomPaint(
        painter: _CablePainter(cables: painted, zoom: widget.camera.zoom),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _note(List<SceneCable> cables) {
    final ids = {for (final cable in cables) cable.id};
    if (!_primed) {
      _known = ids;
      _primed = true;
      _sawDrag = widget.dragFrameId != null;
      _dragSource = widget.dragFrameId;
      _syncTicker();
      return;
    }
    final fromDrag = _sawDrag;
    final dragSource = _dragSource;
    for (final cable in cables) {
      if (_known.contains(cable.id) || _arrivals.containsKey(cable.id)) {
        continue;
      }
      final plan = connectArrival(
        sawDrag: fromDrag,
        dragFrameId: dragSource,
        sourceId: cable.sourceId,
        targetFrameId: cable.targetFrameId,
      );
      _arrivals[cable.id] = _Arrival(_clock, plan);
      widget.motion?.hold(cable.id);
    }
    _known = ids;
    _sawDrag = widget.dragFrameId != null;
    _dragSource = widget.dragFrameId;
    _syncTicker();
  }

  void _pushMotion(List<SceneCable> cables) {
    final motion = widget.motion;
    if (motion == null) {
      return;
    }
    final live = {for (final cable in cables) cable.id};
    for (final id in _arrivals.keys.toList()) {
      if (!live.contains(id)) {
        _arrivals.remove(id);
        motion.release(id);
        continue;
      }
      final arrival = _arrivals[id]!;
      final elapsed = _clock - arrival.start;
      if (elapsed >= _travelSeconds + _settleSeconds) {
        _arrivals.remove(id);
        motion.release(id);
        continue;
      }
      final pose = _pose(arrival, elapsed);
      motion.present(id, pose.shown, pose.glow);
    }
  }

  _Pose _pose(_Arrival arrival, double elapsed) {
    final travel = (elapsed / _travelSeconds).clamp(0.0, 1.0);
    final eased = 1 - math.pow(1 - travel, 3).toDouble();
    final draw = arrival.plan.draw(eased);
    final head = arrival.plan.flash(eased);
    final intoSettle = elapsed <= _travelSeconds
        ? 0.0
        : ((elapsed - _travelSeconds) / _settleSeconds).clamp(0.0, 1.0);
    final flashAlpha = elapsed < _travelSeconds
        ? (travel < 0.07 ? travel / 0.07 : 1.0)
        : (1 - intoSettle / 0.42).clamp(0.0, 1.0);
    final bloom = elapsed < _travelSeconds * 0.9
        ? 0.0
        : _linger(
            ((elapsed - _travelSeconds * 0.9) / _settleSeconds).clamp(0.0, 1.0),
          );
    final shown = elapsed < _travelSeconds
        ? 0.0
        : (intoSettle / 0.5).clamp(0.0, 1.0);
    return _Pose(
      draw: draw,
      flash: flashAlpha > 0.01 ? head : null,
      flashAlpha: flashAlpha,
      arrival: bloom,
      shown: shown,
      glow: bloom * shown,
      towardSource: arrival.plan.towardSource,
    );
  }

  double _linger(double t) {
    if (t < 0.14) {
      return t / 0.14;
    }
    return (1 - (t - 0.14) / 0.86).clamp(0.0, 1.0);
  }

  PaintedCable _paintOf(SceneCable cable) {
    final mark = widget.validation.markOf(cable.id);
    if (mark != null) {
      return PaintedCable(
        from: _screen(_shown(cable.from, cable.sourceId)),
        to: _screen(_shown(cable.to, cable.targetFrameId)),
        color: widget.invalidColor,
        invalid: true,
        danglingStart: mark.dangling == CableDangling.start,
        danglingEnd: mark.dangling == CableDangling.end,
      );
    }
    final arrival = _arrivals[cable.id];
    final pose = arrival == null
        ? null
        : _pose(arrival, _clock - arrival.start);
    final live = pose == null ? _liveOf(cable) : null;
    return PaintedCable(
      from: _screen(_shown(cable.from, cable.sourceId)),
      to: _screen(_shown(cable.to, cable.targetFrameId)),
      color: cable.color,
      draw: pose?.draw ?? 1,
      flash: pose?.flash ?? live?.head,
      flashAlpha: pose?.flashAlpha ?? live?.alpha ?? 1,
      arrival: pose?.arrival ?? 0,
      rest: live?.rest ?? 0,
      flashTowardSource: pose?.towardSource ?? (live?.towardSource ?? false),
      arrivalAtStart: pose?.towardSource ?? (live?.towardSource ?? false),
    );
  }

  _LiveFlash? _liveOf(SceneCable cable) {
    _LiveFlash? rest;
    for (final act in [..._acts.values, ..._fading]) {
      if (!act.cableIds.contains(cable.id)) {
        continue;
      }
      final flash = _flashOf(act, cable);
      if (flash == null) {
        continue;
      }
      if (flash.head != null) {
        return flash;
      }
      rest ??= flash;
    }
    return rest;
  }

  _LiveFlash? _flashOf(_Act act, SceneCable cable) {
    final now = _clock;
    final elapsed = now - act.born;
    if (elapsed < 0) {
      return null;
    }
    final sinceFade = act.released ? now - act.fadeAt : null;
    if (sinceFade != null && sinceFade >= _fadeSeconds) {
      return null;
    }
    final envelope = cableGlowEnvelope(elapsed: elapsed, sinceFade: sinceFade);
    final towardSource = act.towardSource.contains(cable.id);
    final sequencing =
        act.kind == _ActKind.tool || act.kind == _ActKind.toolResult;
    if (sequencing && elapsed >= 0 && (sinceFade == null || sinceFade < 0)) {
      final index = act.cableIds.indexOf(cable.id);
      final active = toolFlashIndex(
        elapsed: elapsed,
        count: act.cableIds.length,
      );
      if (index != active) {
        return _LiveFlash(rest: 0.42 * envelope, towardSource: towardSource);
      }
      final travel = toolFlashTravel(
        elapsed: elapsed,
        count: act.cableIds.length,
      );
      return _LiveFlash(
        head: toolFlashHead(travel: travel, towardSource: towardSource),
        alpha: travel < 0.07 ? travel / 0.07 : 1,
        rest: 0.42 * envelope,
        towardSource: towardSource,
      );
    }
    if (!sequencing &&
        elapsed < _travelSeconds &&
        (sinceFade == null || sinceFade < 0)) {
      final travel = elapsed / _travelSeconds;
      final eased = 1 - math.pow(1 - travel, 3).toDouble();
      return _LiveFlash(
        head: eased,
        alpha: travel < 0.07 ? travel / 0.07 : 1,
        rest: 0.55 * envelope,
      );
    }
    return _LiveFlash(rest: 0.62 * envelope, towardSource: towardSource);
  }

  void _syncActs(List<SceneCable> cables) {
    final activity = widget.activity;
    final body = activity.runningBodyId;
    final desired = <String>{};
    void want(String? token, _ActKind kind, List<SceneCable> members) {
      if (token == null || members.isEmpty) {
        return;
      }
      desired.add(token);
      _keep(token, kind, members);
    }

    want(body == null ? null : 'seed:$body', _ActKind.seed, [
      for (final cable in cables)
        if (body != null &&
            activity.seedPorts.contains(cable.port) &&
            cable.targetBodyId == body)
          cable,
    ]);
    final liveTool = activity.activeToolFrameId;
    final pulsed =
        activity.toolPulse != _seenToolPulse &&
        activity.toolPulseFrameId != null &&
        activity.toolPulseBodyId != null;
    if (activity.toolPulse != _seenToolPulse) {
      _seenToolPulse = activity.toolPulse;
    }
    final resultPulsed =
        activity.toolResultPulse != _seenToolResultPulse &&
        activity.toolResultFrameId != null &&
        activity.toolResultBodyId != null;
    if (activity.toolResultPulse != _seenToolResultPulse) {
      _seenToolResultPulse = activity.toolResultPulse;
    }
    final tool = liveTool ?? (pulsed ? activity.toolPulseFrameId : null);
    final toolBody = liveTool != null
        ? activity.runningBodyId
        : (pulsed ? activity.toolPulseBodyId : null);
    final requestToken = tool == null ? null : 'tool:$tool';
    want(
      requestToken == null || toolBody == null ? null : requestToken,
      _ActKind.tool,
      cablesForToolCall(
        cables: cables,
        toolFrameId: tool ?? '',
        llmBodyId: toolBody ?? '',
      ),
    );
    if (liveTool == null && requestToken != null) {
      final act = _acts[requestToken];
      if (act != null) {
        _release(act);
      }
    }
    final resultTool = resultPulsed ? activity.toolResultFrameId : null;
    final resultBody = resultPulsed ? activity.toolResultBodyId : null;
    if (resultTool != null && resultBody != null) {
      final request = _acts['tool:$resultTool'];
      if (request != null && !request.released) {
        _release(request);
      }
      _spawnToolResult(
        token: 'tool-res:$resultTool',
        members: cablesForToolCall(
          cables: cables,
          toolFrameId: resultTool,
          llmBodyId: resultBody,
          returning: true,
        ),
        born: request != null && request.fadeAt > _clock
            ? request.fadeAt
            : _clock,
        desired: desired,
      );
    }
    final writing = activity.writingBodyId;
    want(writing == null ? null : 'out:$writing', _ActKind.output, [
      for (final cable in cables)
        if (writing != null && cableWritesReply(cable, writing)) cable,
    ]);
    if (body != null) {
      final frame = kitFrameForSelection(
        document: widget.document,
        selectedId: body,
      );
      if (frame != null) {
        desired.add('run:$body');
        _keepRun('run:$body', frame.id);
      }
    }
    for (final token in _acts.keys.toList()) {
      if (desired.contains(token)) {
        continue;
      }
      final existing = _acts.remove(token);
      if (existing == null) {
        continue;
      }
      _release(existing);
      _fading.add(existing);
    }
    _fading.removeWhere((act) => _clock >= act.fadeAt + _fadeSeconds);
    _syncTicker();
  }

  void _keep(String token, _ActKind kind, List<SceneCable> members) {
    final ids = [for (final cable in members) cable.id];
    final frames = switch (kind) {
      _ActKind.seed => {for (final cable in members) cable.sourceId},
      _ActKind.output => {for (final cable in members) cable.targetFrameId},
      _ => {
        for (final cable in members) ...[cable.sourceId, cable.targetFrameId],
      },
    };
    final towardSource = {
      for (final cable in members)
        if (kind != _ActKind.toolResult &&
            (kind == _ActKind.tool ||
                cableActivityTowardSource(cable, widget.activity)))
          cable.id,
    };
    final existing = _acts[token];
    if (existing == null) {
      final act = _Act(
        kind: kind,
        cableIds: ids,
        frames: frames,
        towardSource: towardSource,
        born: _clock,
      );
      _acts[token] = act;
      if (kind == _ActKind.seed) {
        _release(act);
      }
      return;
    }
    existing.cableIds = ids;
    existing.frames = frames;
    existing.towardSource = towardSource;
  }

  void _keepRun(String token, String frameId) {
    final existing = _acts[token];
    if (existing == null) {
      _acts[token] = _Act(
        kind: _ActKind.run,
        cableIds: const [],
        frames: {frameId},
        towardSource: const {},
        born: _clock,
      );
      return;
    }
    existing.frames = {frameId};
  }

  void _release(_Act act) {
    if (act.released) {
      return;
    }
    final now = _clock;
    act.released = true;
    final count = act.cableIds.isEmpty ? 1 : act.cableIds.length;
    act.fadeAt = activityFadeAt(
      born: act.born,
      now: now,
      cycle: act.kind == _ActKind.tool || act.kind == _ActKind.toolResult
          ? count * _travelSeconds
          : _travelSeconds,
      finishCycle: act.kind == _ActKind.tool || act.kind == _ActKind.toolResult,
    );
  }

  void _spawnToolResult({
    required String token,
    required List<SceneCable> members,
    required double born,
    required Set<String> desired,
  }) {
    if (members.isEmpty) {
      return;
    }
    desired.add(token);
    if (_acts.containsKey(token)) {
      return;
    }
    final act = _Act(
      kind: _ActKind.toolResult,
      cableIds: [for (final cable in members) cable.id],
      frames: {
        for (final cable in members) ...[cable.sourceId, cable.targetFrameId],
      },
      towardSource: const {},
      born: born,
    );
    _acts[token] = act;
    _release(act);
  }

  void _publishGlow({required bool notify}) {
    final glow = widget.glow;
    if (glow == null) {
      return;
    }
    final levels = <String, double>{};
    void add(_Act act) {
      final sinceFade = act.released ? _clock - act.fadeAt : null;
      if (sinceFade != null && sinceFade >= _fadeSeconds) {
        return;
      }
      final amount = cableGlowEnvelope(
        elapsed: _clock - act.born,
        sinceFade: sinceFade,
      );
      if (amount <= 0.01) {
        return;
      }
      for (final frame in act.frames) {
        final previous = levels[frame] ?? 0;
        if (amount > previous) {
          levels[frame] = amount;
        }
      }
    }

    for (final act in _acts.values) {
      add(act);
    }
    for (final act in _fading) {
      add(act);
    }
    glow.publish(levels, notify: notify);
  }

  List<PaintedCable> _retracts() {
    final painted = <PaintedCable>[];
    for (final item in widget.retractions) {
      final from = _screen(item.from);
      final to = _screen(item.to);
      final left = cableRetractSpan(
        towardEnd: false,
        cut: item.cut,
        progress: item.progress,
      );
      final right = cableRetractSpan(
        towardEnd: true,
        cut: item.cut,
        progress: item.progress,
      );
      painted.add(
        PaintedCable(
          from: from,
          to: to,
          color: item.color,
          drawStart: left.start,
          draw: left.end,
        ),
      );
      painted.add(
        PaintedCable(
          from: from,
          to: to,
          color: item.color,
          drawStart: right.start,
          draw: right.end,
        ),
      );
    }
    return painted;
  }

  void _syncTicker() {
    final live =
        _arrivals.isNotEmpty ||
        widget.retractions.isNotEmpty ||
        _fading.isNotEmpty ||
        _acts.values.any(_actIsMoving);
    if (live && !_ticker.isActive) {
      _ticker.start();
    } else if (!live && _ticker.isActive) {
      _ticker.stop();
    }
  }

  bool _actIsMoving(_Act act) {
    if (act.released) {
      return _clock < act.fadeAt + _fadeSeconds;
    }
    if (act.kind == _ActKind.tool || act.kind == _ActKind.toolResult) {
      return true;
    }
    if (act.kind == _ActKind.run) {
      return _clock - act.born < cableGlowInSeconds;
    }
    return _clock - act.born < _travelSeconds;
  }

  List<PaintedCable> _drag() {
    if (!widget.paintDrag) {
      return const [];
    }
    final dragId = widget.dragFrameId;
    final cursor = widget.dragCursor;
    final kind = widget.dragKind;
    if (dragId == null || cursor == null || kind == null) {
      return const [];
    }
    final frame = widget.document.objectById(dragId);
    if (frame == null) {
      return const [];
    }
    final snapped = _snap(kind, cursor, frame);
    final refused = snapped == null
        ? cableDragRefusal(widget.document, frame.id, kind, cursor)
        : null;
    final landing = snapped ?? refused?.port;
    final target = landing == null
        ? null
        : widget.document.objectById(landing.frameId);
    final fromIsRight = kitPortIsOutput(kind);
    final toIsRight = landing == null
        ? !fromIsRight
        : kitPortIsOutput(landing.kind);
    return [
      PaintedCable(
        from: _screen(_shown(_center(frame, kind), frame.id)),
        to: _screen(landing?.center ?? cursor),
        color: refused != null
            ? widget.invalidColor
            : target == null
            ? kitAccentColor(frame)
            : kitAccentColor(target),
        preview: true,
        invalid: refused != null,
        exitsRight: fromIsRight,
        entersFromLeft: !toIsRight,
      ),
    ];
  }

  KitPort? _snap(KitPortKind sourceKind, Offset cursor, SceneObject source) {
    final hit = hitKitPort(kitPorts(widget.document), cursor);
    if (hit == null || !kitPortsConnect(sourceKind, hit.kind)) {
      return null;
    }
    final sourcePort = kitPorts(widget.document)
        .where((port) => port.frameId == source.id && port.kind == sourceKind)
        .firstOrNull;
    if (sourcePort != null && sourcePort.peerId == hit.peerId) {
      return null;
    }
    return hit;
  }

  Offset _center(SceneObject frame, KitPortKind kind) {
    return kitPortCenter(frame, kitPortSpecOf(kind));
  }

  Offset _shown(Offset center, String id) {
    if (widget.previewIds.contains(id)) {
      return center + widget.previewDelta;
    }
    return center;
  }

  Offset _screen(Offset world) {
    return worldToScreen(world, widget.viewportSize, widget.camera);
  }
}

class _CablePainter extends CustomPainter {
  const _CablePainter({required this.cables, required this.zoom});

  final List<PaintedCable> cables;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    paintCables(canvas, cables, zoom);
  }

  @override
  bool shouldRepaint(covariant _CablePainter oldDelegate) {
    if (oldDelegate.zoom != zoom ||
        oldDelegate.cables.length != cables.length) {
      return true;
    }
    for (var i = 0; i < cables.length; i++) {
      final previous = oldDelegate.cables[i];
      final next = cables[i];
      if (previous.from != next.from ||
          previous.to != next.to ||
          previous.color != next.color ||
          previous.preview != next.preview ||
          previous.drawStart != next.drawStart ||
          previous.draw != next.draw ||
          previous.flash != next.flash ||
          previous.flashAlpha != next.flashAlpha ||
          previous.arrival != next.arrival ||
          previous.flow != next.flow ||
          previous.flashTowardSource != next.flashTowardSource ||
          previous.arrivalAtStart != next.arrivalAtStart ||
          previous.rest != next.rest) {
        return true;
      }
    }
    return false;
  }
}

enum _ActKind { seed, tool, toolResult, output, run }

class _Act {
  _Act({
    required this.kind,
    required this.cableIds,
    required this.frames,
    required this.towardSource,
    required this.born,
  });

  final _ActKind kind;
  List<String> cableIds;
  Set<String> frames;
  Set<String> towardSource;
  final double born;
  var released = false;
  var fadeAt = 0.0;
}

class _LiveFlash {
  const _LiveFlash({
    this.head,
    this.alpha = 0,
    this.rest = 0,
    this.towardSource = false,
  });

  final double? head;
  final double alpha;
  final double rest;
  final bool towardSource;
}

class _Arrival {
  const _Arrival(this.start, this.plan);

  final double start;
  final ConnectArrival plan;
}

class _Pose {
  const _Pose({
    required this.draw,
    required this.flash,
    required this.flashAlpha,
    required this.arrival,
    required this.shown,
    required this.glow,
    required this.towardSource,
  });

  final double draw;
  final double? flash;
  final double flashAlpha;
  final double arrival;
  final double shown;
  final double glow;
  final bool towardSource;
}
