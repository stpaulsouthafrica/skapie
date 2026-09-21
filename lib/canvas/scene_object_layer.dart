import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit_mark.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
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
    this.selectedId,
    this.previewDelta = Offset.zero,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final List<SceneObject> objects;
  final ObjectRegistry registry;
  final String? selectedId;
  final Offset previewDelta;

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
    final preview = object.id == selectedId ? previewDelta : Offset.zero;
    final topLeft = worldToScreen(
      Offset(object.x + preview.dx, object.y + preview.dy),
      viewportSize,
      camera,
    );
    final ctx = RegistryBuildContext(zoom: camera.zoom);
    Widget child = SizedBox(
      width: object.width * camera.zoom,
      height: object.height * camera.zoom,
      child: registry.build(context, object, ctx: ctx),
    );
    if (object.props[skapieKitProp] == harnessLlmKitId &&
        object.props[skapieRoleProp] == 'frame') {
      final tokens = PaintScope.of(context);
      final mark = (10.0 * camera.zoom).clamp(8.0, 16.0);
      child = Stack(
        children: [
          child,
          Positioned(
            left: 6 * camera.zoom,
            top: 6 * camera.zoom,
            child: LlmKitMark(
              key: const Key('llm-kit-mark'),
              color: tokens.accent,
              size: mark,
            ),
          ),
        ],
      );
    }
    if (object.rotation != 0) {
      child = Transform.rotate(angle: object.rotation, child: child);
    }
    return Positioned(left: topLeft.dx, top: topLeft.dy, child: child);
  }
}
