import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/paint/cables/cable_hit.dart';
import 'package:skapie/paint/cables/cable_painter.dart';

void main() {
  const cable = SceneCable(
    id: 'a|b|input',
    ownerId: 'a',
    port: 'input',
    sourceId: 'a',
    targetFrameId: 'f',
    from: Offset.zero,
    to: Offset(200, 0),
    color: Color(0xFF88C0A8),
    targetBodyId: 'b',
    affectsRun: true,
  );

  test('a pointer on the cable hits, and one off it does not', () {
    final hit = hitCable(
      cables: const [cable],
      screenPoint: const Offset(100, 2),
      worldEnds: (item) => (from: item.from, to: item.to),
      toScreen: (point) => point,
      zoom: 1,
    );
    expect(hit, isNotNull);
    expect(hit!.t, greaterThan(0.4));
    expect(hit.t, lessThan(0.6));

    expect(
      hitCable(
        cables: const [cable],
        screenPoint: const Offset(100, 40),
        worldEnds: (item) => (from: item.from, to: item.to),
        toScreen: (point) => point,
        zoom: 1,
      ),
      isNull,
    );
  });

  test('a cut retracts both halves away from the cut', () {
    final left = cableRetractSpan(towardEnd: false, cut: 0.4, progress: 0);
    final right = cableRetractSpan(towardEnd: true, cut: 0.4, progress: 0);
    expect(left.start, 0);
    expect(left.end, 0.4);
    expect(right.start, 0.4);
    expect(right.end, 1);

    final laterLeft = cableRetractSpan(towardEnd: false, cut: 0.4, progress: 1);
    final laterRight = cableRetractSpan(towardEnd: true, cut: 0.4, progress: 1);
    expect(laterLeft.end, 0);
    expect(laterRight.start, 1);

    final midLeft = cableRetractSpan(towardEnd: false, cut: 0.4, progress: 0.5);
    expect(midLeft.end, lessThan(0.4));
    expect(midLeft.end, greaterThan(0));
  });

  test('dragging from an input back to an output keeps the same curve', () {
    const output = Offset(0, 40);
    const input = Offset(200, 0);
    final committed = cableCurve(output, input, 1);
    final drag = cableCurve(
      input,
      output,
      1,
      exitsRight: false,
      entersFromLeft: false,
    );
    final forward = committed.computeMetrics().single;
    final reverse = drag.computeMetrics().single;
    expect(reverse.length, closeTo(forward.length, 0.01));
    for (final t in [0.25, 0.5, 0.75]) {
      final onCommit = forward
          .getTangentForOffset(forward.length * t)!
          .position;
      final onDrag = reverse
          .getTangentForOffset(reverse.length * (1 - t))!
          .position;
      expect(onDrag.dx, closeTo(onCommit.dx, 0.01));
      expect(onDrag.dy, closeTo(onCommit.dy, 0.01));
    }
  });
}
