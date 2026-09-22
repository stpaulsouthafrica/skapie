import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/paint/cables/cable_hit.dart';

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
}
