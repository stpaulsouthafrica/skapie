import 'dart:ui';

/// World-to-screen scale limits.
const double minZoom = 0.25;
const double maxZoom = 4.0;

double clampZoom(double zoom) => zoom.clamp(minZoom, maxZoom);

/// Camera for the infinite canvas.
///
/// Convention:
/// - Screen origin is the viewport top-left; +x right, +y down (Flutter).
/// - World uses the same axis directions.
/// - [offset] is the world point shown at the viewport center.
/// - [zoom] is world-to-screen scale (`2.0` means 1 world unit = 2 screen px).
///
/// Default camera (`offset = (0,0)`, `zoom = 1`) places world origin at the
/// viewport center.
///
///     worldToScreen(world) = (world - offset) * zoom + viewportCenter
///     screenToWorld(screen) = (screen - viewportCenter) / zoom + offset
final class CanvasCamera {
  CanvasCamera({this.offset = Offset.zero, double zoom = 1.0})
    : zoom = clampZoom(zoom);

  /// World point displayed at the viewport center.
  final Offset offset;

  /// World-to-screen scale, clamped to [minZoom]–[maxZoom].
  final double zoom;

  @override
  bool operator ==(Object other) {
    return other is CanvasCamera &&
        other.offset == offset &&
        other.zoom == zoom;
  }

  @override
  int get hashCode => Object.hash(offset, zoom);

  CanvasCamera copyWith({Offset? offset, double? zoom}) {
    return CanvasCamera(offset: offset ?? this.offset, zoom: zoom ?? this.zoom);
  }

  /// Move the paper with the pointer: a positive screen delta (pointer moved
  /// right/down) keeps the grabbed world point under the cursor.
  CanvasCamera panScreen(Offset screenDelta) {
    return CanvasCamera(offset: offset - screenDelta / zoom, zoom: zoom);
  }

  /// Change zoom while keeping the world point under [cursor] fixed.
  CanvasCamera zoomAt({
    required Offset cursor,
    required Size viewportSize,
    double? factor,
    double? zoom,
  }) {
    final worldUnderCursor = screenToWorld(cursor, viewportSize, this);
    final nextZoom = clampZoom(zoom ?? this.zoom * (factor ?? 1));
    final viewportCenter = viewportSize.center(Offset.zero);
    final nextOffset = worldUnderCursor - (cursor - viewportCenter) / nextZoom;
    return CanvasCamera(offset: nextOffset, zoom: nextZoom);
  }

  CanvasCamera reset() => CanvasCamera();
}

Offset screenToWorld(Offset screen, Size viewportSize, CanvasCamera camera) {
  final viewportCenter = viewportSize.center(Offset.zero);
  return (screen - viewportCenter) / camera.zoom + camera.offset;
}

Offset worldToScreen(Offset world, Size viewportSize, CanvasCamera camera) {
  final viewportCenter = viewportSize.center(Offset.zero);
  return (world - camera.offset) * camera.zoom + viewportCenter;
}
