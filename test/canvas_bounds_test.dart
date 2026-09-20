import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/canvas_bounds.dart';
import 'package:skapie/scene/scene_object.dart';

SceneObject _rect(
  String id, {
  required double x,
  required double y,
  required double width,
  required double height,
  bool visible = true,
}) {
  return SceneObject(
    id: id,
    type: 'debug.rect',
    x: x,
    y: y,
    width: width,
    height: height,
    visible: visible,
  );
}

bool _inclusiveContains(Rect rect, Offset point) {
  return point.dx >= rect.left &&
      point.dx <= rect.right &&
      point.dy >= rect.top &&
      point.dy <= rect.bottom;
}

void main() {
  test('union bounds of two rectangles', () {
    final bounds = contentBounds([
      _rect('a', x: 0, y: 0, width: 10, height: 10),
      _rect('b', x: 20, y: 5, width: 10, height: 10),
    ]);

    expect(bounds.left, 0);
    expect(bounds.top, 0);
    expect(bounds.right, 30);
    expect(bounds.bottom, 15);
  });

  test('invisible objects are ignored', () {
    final bounds = contentBounds([
      _rect('hidden', x: 1000, y: 1000, width: 10, height: 10, visible: false),
      _rect('shown', x: 0, y: 0, width: 8, height: 8),
    ]);

    expect(bounds, const Rect.fromLTWH(0, 0, 8, 8));
  });

  test('empty scene fallback contains the world origin', () {
    final bounds = contentBounds(const []);

    expect(bounds.width, emptyContentWidth);
    expect(bounds.height, emptyContentHeight);
    expect(bounds.center, Offset.zero);
    expect(_inclusiveContains(bounds, Offset.zero), isTrue);
  });

  test('offset outside padded rect clamps to the edge', () {
    const content = Rect.fromLTWH(0, 0, 100, 80);
    const viewport = Size(400, 300);
    const zoom = 1.0;
    final padded = paddedContentBounds(
      content: content,
      viewportSize: viewport,
      zoom: zoom,
    );

    final clamped = clampCameraOffset(const Offset(10000, -4000), padded);

    expect(clamped.dx, padded.right);
    expect(clamped.dy, padded.top);
  });

  test('after clamp, viewport center is inside the padded rect', () {
    const content = Rect.fromLTWH(-50, -20, 40, 30);
    const viewport = Size(800, 600);
    final padded = paddedContentBounds(
      content: content,
      viewportSize: viewport,
      zoom: 2,
    );

    final clamped = clampCameraOffset(const Offset(-999, 999), padded);

    expect(_inclusiveContains(padded, clamped), isTrue);
  });
}
