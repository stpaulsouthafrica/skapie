import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/canvas_camera.dart';

void main() {
  const viewport = Size(800, 600);
  const center = Offset(400, 300);
  const epsilon = 1e-9;

  Matcher closeOffset(Offset expected) => predicate<Offset>((actual) {
    return (actual.dx - expected.dx).abs() < epsilon &&
        (actual.dy - expected.dy).abs() < epsilon;
  }, 'Offset close to $expected');

  group('identity camera', () {
    test('viewport center maps to world origin', () {
      final camera = CanvasCamera();

      expect(screenToWorld(center, viewport, camera), closeOffset(Offset.zero));
      expect(worldToScreen(Offset.zero, viewport, camera), closeOffset(center));
    });
  });

  group('round-trip', () {
    final cameras = [
      CanvasCamera(),
      CanvasCamera(zoom: 0.5),
      CanvasCamera(zoom: 2.5),
      CanvasCamera(offset: const Offset(120, -80), zoom: 1.75),
    ];
    final points = [
      Offset.zero,
      center,
      const Offset(12, 24),
      const Offset(799, 599),
      const Offset(400.5, 1.25),
    ];

    for (final camera in cameras) {
      for (final screen in points) {
        test(
          'screen → world → screen at zoom ${camera.zoom} offset ${camera.offset} point $screen',
          () {
            final world = screenToWorld(screen, viewport, camera);
            final back = worldToScreen(world, viewport, camera);
            expect(back, closeOffset(screen));
          },
        );
      }
    }
  });

  group('zoom clamp', () {
    test('clamps values below min', () {
      expect(CanvasCamera(zoom: 0.01).zoom, minZoom);
      expect(clampZoom(0.01), minZoom);
    });

    test('clamps values above max', () {
      expect(CanvasCamera(zoom: 99).zoom, maxZoom);
      expect(clampZoom(8), maxZoom);
    });

    test('leaves in-range zoom unchanged', () {
      expect(CanvasCamera(zoom: 1.5).zoom, 1.5);
      expect(clampZoom(1.0), 1.0);
    });
  });

  group('zoom at point', () {
    test('world point under the cursor stays stable when zooming in', () {
      final camera = CanvasCamera(offset: const Offset(40, -15), zoom: 1.0);
      const cursor = Offset(220, 140);
      final worldBefore = screenToWorld(cursor, viewport, camera);

      final zoomed = camera.zoomAt(
        cursor: cursor,
        viewportSize: viewport,
        factor: 2,
      );

      expect(zoomed.zoom, 2.0);
      expect(screenToWorld(cursor, viewport, zoomed), closeOffset(worldBefore));
    });

    test('world point under the cursor stays stable when zooming out', () {
      final camera = CanvasCamera(offset: const Offset(-30, 90), zoom: 2.0);
      const cursor = Offset(610, 410);
      final worldBefore = screenToWorld(cursor, viewport, camera);

      final zoomed = camera.zoomAt(
        cursor: cursor,
        viewportSize: viewport,
        factor: 0.5,
      );

      expect(zoomed.zoom, 1.0);
      expect(screenToWorld(cursor, viewport, zoomed), closeOffset(worldBefore));
    });

    test('zoom-at-point still clamps', () {
      final camera = CanvasCamera(zoom: maxZoom);
      const cursor = Offset(10, 10);
      final zoomed = camera.zoomAt(
        cursor: cursor,
        viewportSize: viewport,
        factor: 3,
      );
      expect(zoomed.zoom, maxZoom);
    });
  });
}
