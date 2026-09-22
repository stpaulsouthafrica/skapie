import 'package:flutter/material.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/paint/cables/cable_painter.dart';

const double cableCutSlop = 8;
const Duration cableRetractDuration = Duration(milliseconds: 340);

class CableHover {
  const CableHover({
    required this.cable,
    required this.t,
    required this.screen,
    required this.from,
    required this.to,
  });

  final SceneCable cable;

  /// 0 at the source port, 1 at the target port.
  final double t;
  final Offset screen;

  /// World endpoints of the curve under the pointer, including any drag.
  final Offset from;
  final Offset to;
}

class CableRetractSpan {
  const CableRetractSpan(this.start, this.end);

  final double start;
  final double end;
}

/// Ease-out. The loose ends leave the cut quickly, like a tape measure.
double cableRetractEase(double t) {
  final x = t.clamp(0.0, 1.0);
  return 1 - (1 - x) * (1 - x);
}

/// One half of a cut cable shrinking toward its port.
CableRetractSpan cableRetractSpan({
  required bool towardEnd,
  required double cut,
  required double progress,
}) {
  final eased = cableRetractEase(progress);
  if (!towardEnd) {
    return CableRetractSpan(0, cut * (1 - eased));
  }
  return CableRetractSpan(cut + (1 - cut) * eased, 1);
}

class RetractingCable {
  RetractingCable({
    required this.from,
    required this.to,
    required this.cut,
    required this.color,
  }) : started = DateTime.now();

  final Offset from;
  final Offset to;
  final double cut;
  final Color color;
  final DateTime started;

  double get progress {
    final elapsed = DateTime.now().difference(started).inMicroseconds;
    return (elapsed / cableRetractDuration.inMicroseconds).clamp(0.0, 1.0);
  }
}

typedef CableWorldEnds = ({Offset from, Offset to});

/// Nearest point on a cable curve, in screen space. Null when the pointer
/// is farther than [slop] pixels from every cable.
CableHover? hitCable({
  required List<SceneCable> cables,
  required Offset screenPoint,
  required CableWorldEnds Function(SceneCable cable) worldEnds,
  required Offset Function(Offset world) toScreen,
  required double zoom,
  double slop = cableCutSlop,
}) {
  CableHover? best;
  var bestDistance = slop * slop;
  for (final cable in cables) {
    final ends = worldEnds(cable);
    final from = toScreen(ends.from);
    final to = toScreen(ends.to);
    final metrics = cableCurve(from, to, zoom).computeMetrics().toList();
    if (metrics.isEmpty || metrics.first.length <= 0) {
      continue;
    }
    final metric = metrics.first;
    const step = 4.0;
    for (var dist = 0.0; dist <= metric.length; dist += step) {
      final tangent = metric.getTangentForOffset(
        dist.clamp(0.0, metric.length),
      );
      if (tangent == null) {
        continue;
      }
      final delta = tangent.position - screenPoint;
      final distance = delta.dx * delta.dx + delta.dy * delta.dy;
      if (distance > bestDistance) {
        continue;
      }
      bestDistance = distance;
      best = CableHover(
        cable: cable,
        t: dist / metric.length,
        screen: tangent.position,
        from: ends.from,
        to: ends.to,
      );
    }
  }
  return best;
}
