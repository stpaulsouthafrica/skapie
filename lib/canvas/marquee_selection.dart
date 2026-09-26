import 'package:flutter/material.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/cables/cable_painter.dart';
import 'package:skapie/scene/scene.dart';

typedef MarqueeHits = ({Set<String> objectIds, Set<String> cableIds});

/// Hit test visible kit frames and cable strokes against a screen-space box.
MarqueeHits hitMarquee({
  required Rect rect,
  required List<SceneObject> objects,
  required List<SceneCable> cables,
  required Offset Function(Offset world) toScreen,
  required double zoom,
}) {
  final objectIds = <String>{};
  for (final object in objects) {
    if (!object.visible ||
        (isKitObject(object) && object.props[skapieRoleProp] != 'frame')) {
      continue;
    }
    final topLeft = toScreen(Offset(object.x, object.y));
    final objectRect = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      object.width * zoom,
      object.height * zoom,
    );
    if (rect.overlaps(objectRect)) objectIds.add(object.id);
  }

  final cableIds = <String>{};
  for (final cable in cables) {
    final path = cableCurve(toScreen(cable.from), toScreen(cable.to), zoom);
    if (!path.getBounds().overlaps(rect)) continue;
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance <= metric.length; distance += 4) {
        final point = metric.getTangentForOffset(distance)?.position;
        if (point != null && rect.inflate(2).contains(point)) {
          cableIds.add(cable.id);
          break;
        }
      }
      if (cableIds.contains(cable.id)) break;
    }
  }
  return (objectIds: objectIds, cableIds: cableIds);
}
