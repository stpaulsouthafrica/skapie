import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/cables/cable_hit.dart';
import 'package:skapie/paint/cables/cable_motion.dart';
import 'package:skapie/paint/cables/cable_painter.dart';
import 'package:skapie/scene/scene.dart';

const double _travelSeconds = 0.32;
const double _settleSeconds = 0.52;
const double _flowSeconds = 1.45;

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
    this.previewOnly = false,
    this.paintDrag = true,
    this.runningBodyId,
    this.motion,
    this.retractions = const [],
    this.onRetractionDone,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final SceneDocument document;
  final Offset previewDelta;
  final Set<String> previewIds;
  final String? dragFrameId;
  final KitPortKind? dragKind;
  final Offset? dragCursor;
  final bool previewOnly;
  final bool paintDrag;
  final String? runningBodyId;
  final CableMotion? motion;
  final List<RetractingCable> retractions;
  final ValueChanged<RetractingCable>? onRetractionDone;

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

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!mounted) {
        return;
      }
      _pushMotion(sceneCables(widget.document));
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
        : sceneCables(widget.document);
    if (!widget.previewOnly) {
      _note(scene);
    }
    final painted = <PaintedCable>[
      for (final cable in scene) _paintOf(cable),
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
      return;
    }
    final fromDrag = _sawDrag;
    final dragSource = _dragSource;
    for (final cable in cables) {
      if (_known.contains(cable.id) || _arrivals.containsKey(cable.id)) {
        continue;
      }
      final grewFromDrag = fromDrag && cable.sourceId == dragSource;
      _arrivals[cable.id] = _Arrival(_clock, grow: !grewFromDrag);
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
    final draw = arrival.grow ? eased : 1.0;
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
      flash: flashAlpha > 0.01 ? eased : null,
      flashAlpha: flashAlpha,
      arrival: bloom,
      shown: shown,
      glow: bloom * shown,
    );
  }

  double _linger(double t) {
    if (t < 0.14) {
      return t / 0.14;
    }
    return (1 - (t - 0.14) / 0.86).clamp(0.0, 1.0);
  }

  PaintedCable _paintOf(SceneCable cable) {
    final arrival = _arrivals[cable.id];
    final pose = arrival == null
        ? null
        : _pose(arrival, _clock - arrival.start);
    return PaintedCable(
      from: _screen(_shown(cable.from, cable.sourceId)),
      to: _screen(_shown(cable.to, cable.targetFrameId)),
      color: cable.color,
      draw: pose?.draw ?? 1,
      flash: pose?.flash,
      flashAlpha: pose?.flashAlpha ?? 1,
      arrival: pose?.arrival ?? 0,
      flow: _flow(cable),
    );
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
        widget.runningBodyId != null ||
        widget.retractions.isNotEmpty;
    if (live && !_ticker.isActive) {
      _ticker.start();
    } else if (!live && _ticker.isActive) {
      _ticker.stop();
    }
  }

  double? _flow(SceneCable cable) {
    final running = widget.runningBodyId;
    if (running == null || !cable.affectsRun || cable.targetBodyId != running) {
      return null;
    }
    return (_clock / _flowSeconds) % 1;
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
    final target = snapped == null
        ? null
        : widget.document.objectById(snapped.frameId);
    return [
      PaintedCable(
        from: _screen(_shown(_center(frame, kind), frame.id)),
        to: _screen(snapped?.center ?? cursor),
        color: target == null ? kitAccentColor(frame) : kitAccentColor(target),
        preview: true,
      ),
    ];
  }

  KitPort? _snap(KitPortKind sourceKind, Offset cursor, SceneObject source) {
    final hit = hitKitPort(kitPorts(widget.document), cursor);
    if (hit == null || !kitPortAccepts(sourceKind, hit.kind)) {
      return null;
    }
    if (sourceKind == KitPortKind.llmOutput) {
      final sourcePort = kitPorts(widget.document)
          .where(
            (port) =>
                port.frameId == source.id && port.kind == KitPortKind.llmOutput,
          )
          .firstOrNull;
      if (sourcePort != null && sourcePort.peerId == hit.peerId) {
        return null;
      }
    }
    return hit;
  }

  Offset _center(SceneObject frame, KitPortKind kind) {
    return switch (kind) {
      KitPortKind.textOut ||
      KitPortKind.conversationOut => textOutputCenter(frame),
      KitPortKind.toolOut => toolOutputCenter(frame),
      KitPortKind.llmInput => llmInputCenter(frame),
      KitPortKind.llmContext => llmContextCenter(frame),
      KitPortKind.llmConversation => llmConversationCenter(frame),
      KitPortKind.llmTools => llmToolsCenter(frame),
      KitPortKind.llmOutput => llmOutputCenter(frame),
    };
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
          previous.flow != next.flow) {
        return true;
      }
    }
    return false;
  }
}

class _Arrival {
  const _Arrival(this.start, {required this.grow});

  final double start;
  final bool grow;
}

class _Pose {
  const _Pose({
    required this.draw,
    required this.flash,
    required this.flashAlpha,
    required this.arrival,
    required this.shown,
    required this.glow,
  });

  final double draw;
  final double? flash;
  final double flashAlpha;
  final double arrival;
  final double shown;
  final double glow;
}
