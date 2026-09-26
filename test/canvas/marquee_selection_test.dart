import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/marquee_selection.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  const frame = SceneObject(
    id: 'kit',
    type: 'box',
    x: -120,
    y: -30,
    width: 70,
    height: 60,
    props: {skapieKitProp: 'example', skapieRoleProp: 'frame'},
  );
  const body = SceneObject(
    id: 'body',
    type: 'box',
    x: -115,
    y: -25,
    width: 60,
    height: 50,
    props: {skapieKitProp: 'example', skapieRoleProp: 'body'},
  );
  const hidden = SceneObject(
    id: 'hidden',
    type: 'box',
    x: 50,
    y: -30,
    width: 70,
    height: 60,
    visible: false,
    props: {skapieKitProp: 'example', skapieRoleProp: 'frame'},
  );
  const cable = SceneCable(
    id: 'cable',
    ownerId: 'kit',
    port: 'input',
    sourceId: 'kit',
    targetFrameId: 'hidden',
    from: Offset(-40, 0),
    to: Offset(40, 0),
    color: Colors.green,
    targetBodyId: 'hidden',
    affectsRun: true,
  );

  test('marquee finds kit frames but skips their bodies and hidden kits', () {
    final hits = hitMarquee(
      rect: const Rect.fromLTWH(-130, -40, 80, 80),
      objects: [frame, body, hidden],
      cables: [cable],
      toScreen: (world) => world,
      zoom: 1,
    );
    expect(hits.objectIds, {'kit'});
    expect(hits.cableIds, isEmpty);
  });

  test('marquee selects a cable crossed between both kits', () {
    final hits = hitMarquee(
      rect: Rect.fromPoints(const Offset(10, 10), const Offset(-10, -10)),
      objects: [frame, body, hidden],
      cables: [cable],
      toScreen: (world) => world,
      zoom: 1,
    );
    expect(hits.objectIds, isEmpty);
    expect(hits.cableIds, {'cable'});
  });
}
