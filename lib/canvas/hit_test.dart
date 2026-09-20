import 'dart:ui';

import 'package:skapie/scene/scene_object.dart';

/// World-space AABB hit-test. Rotation is ignored (same as camera bounds).
SceneObject? hitTestObjects(List<SceneObject> objects, Offset world) {
  SceneObject? hit;
  for (final object in objects) {
    if (!object.visible) {
      continue;
    }
    if (!_contains(object, world)) {
      continue;
    }
    if (hit == null || object.zIndex >= hit.zIndex) {
      hit = object;
    }
  }
  return hit;
}

bool objectAllowsMove(SceneObject object) => !object.locked;

bool _contains(SceneObject object, Offset world) {
  return world.dx >= object.x &&
      world.dx <= object.x + object.width &&
      world.dy >= object.y &&
      world.dy <= object.y + object.height;
}
