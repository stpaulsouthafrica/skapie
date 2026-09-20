import 'dart:math' as math;
import 'dart:ui';

import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/scene/scene_object.dart';

/// Fallback content box when the scene has no visible objects.
/// Centered on the world origin.
const double emptyContentWidth = 2000;
const double emptyContentHeight = 2000;

/// Minimum padding in world units on each side of content bounds.
const double minWorldPad = 200;

/// Extra padding as a fraction of the viewport size in world units.
const double contentPadFraction = 0.35;

Rect get emptyContentBounds => Rect.fromCenter(
  center: Offset.zero,
  width: emptyContentWidth,
  height: emptyContentHeight,
);

/// Axis-aligned union of visible scene object frames (unrotated x,y,w,h).
///
/// Empty or all-invisible → [emptyContentBounds] around the world origin.
Rect contentBounds(Iterable<SceneObject> objects) {
  Rect? union;
  for (final object in objects) {
    if (!object.visible) {
      continue;
    }
    final frame = Rect.fromLTWH(
      object.x,
      object.y,
      object.width,
      object.height,
    );
    union = union == null ? frame : union.expandToInclude(frame);
  }
  return union ?? emptyContentBounds;
}

/// Inflate [content] so the camera can travel a bit past the objects.
Rect paddedContentBounds({
  required Rect content,
  required Size viewportSize,
  required double zoom,
}) {
  final safeZoom = zoom <= 0 ? minZoom : zoom;
  final viewportWorldWidth = viewportSize.width / safeZoom;
  final viewportWorldHeight = viewportSize.height / safeZoom;
  final padX = math.max(minWorldPad, viewportWorldWidth * contentPadFraction);
  final padY = math.max(minWorldPad, viewportWorldHeight * contentPadFraction);
  return Rect.fromLTRB(
    content.left - padX,
    content.top - padY,
    content.right + padX,
    content.bottom + padY,
  );
}

/// Inclusive clamp of the camera offset (world point at viewport center).
Offset clampCameraOffset(Offset offset, Rect padded) {
  return Offset(
    offset.dx.clamp(padded.left, padded.right),
    offset.dy.clamp(padded.top, padded.bottom),
  );
}

/// Hard-clamp [camera] so the viewport center stays in padded content bounds.
CanvasCamera clampCameraToContent({
  required CanvasCamera camera,
  required Size viewportSize,
  required Iterable<SceneObject> objects,
}) {
  if (viewportSize.isEmpty) {
    return camera;
  }
  final padded = paddedContentBounds(
    content: contentBounds(objects),
    viewportSize: viewportSize,
    zoom: camera.zoom,
  );
  final nextOffset = clampCameraOffset(camera.offset, padded);
  if (nextOffset == camera.offset) {
    return camera;
  }
  return camera.copyWith(offset: nextOffset);
}
