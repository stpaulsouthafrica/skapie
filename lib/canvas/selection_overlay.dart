import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene_object.dart';

/// Screen-space selection stroke. Rotation is ignored for v1.
class SceneSelectionOverlay extends StatelessWidget {
  const SceneSelectionOverlay({
    super.key,
    required this.camera,
    required this.viewportSize,
    required this.object,
    this.previewDelta = Offset.zero,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final SceneObject object;
  final Offset previewDelta;

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final topLeft = worldToScreen(
      Offset(object.x + previewDelta.dx, object.y + previewDelta.dy),
      viewportSize,
      camera,
    );
    final radius = kitCornerRadius(object) * camera.zoom;
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: IgnorePointer(
        child: SizedBox(
          width: object.width * camera.zoom,
          height: object.height * camera.zoom,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: tokens.accent,
                width: camera.zoom,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
