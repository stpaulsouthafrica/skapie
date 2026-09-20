import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene_object.dart';

/// Places registered scene objects in world space. Does not mutate the scene.
class SceneObjectLayer extends StatelessWidget {
  const SceneObjectLayer({
    super.key,
    required this.camera,
    required this.viewportSize,
    required this.objects,
    required this.registry,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final List<SceneObject> objects;
  final ObjectRegistry registry;

  @override
  Widget build(BuildContext context) {
    if (viewportSize.isEmpty) {
      return const SizedBox.expand();
    }
    final ordered = [
      for (final object in objects)
        if (object.visible) object,
    ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [for (final object in ordered) _placed(context, object)],
      ),
    );
  }

  Widget _placed(BuildContext context, SceneObject object) {
    final topLeft = worldToScreen(
      Offset(object.x, object.y),
      viewportSize,
      camera,
    );
    final ctx = RegistryBuildContext(zoom: camera.zoom);
    Widget child = SizedBox(
      width: object.width * camera.zoom,
      height: object.height * camera.zoom,
      child: registry.build(context, object, ctx: ctx),
    );
    if (object.rotation != 0) {
      child = Transform.rotate(angle: object.rotation, child: child);
    }
    return Positioned(left: topLeft.dx, top: topLeft.dy, child: child);
  }
}
