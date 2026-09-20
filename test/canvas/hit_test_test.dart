import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/hit_test.dart';
import 'package:skapie/scene/scene_object.dart';

SceneObject _object(
  String id, {
  double x = 0,
  double y = 0,
  double width = 10,
  double height = 10,
  int zIndex = 0,
  bool visible = true,
  bool locked = false,
}) {
  return SceneObject(
    id: id,
    type: 'box',
    x: x,
    y: y,
    width: width,
    height: height,
    zIndex: zIndex,
    visible: visible,
    locked: locked,
  );
}

void main() {
  test('picks the topmost visible object', () {
    final objects = [
      _object('low', x: 0, y: 0, zIndex: 0),
      _object('high', x: 0, y: 0, zIndex: 2),
      _object('mid', x: 0, y: 0, zIndex: 1),
    ];
    expect(hitTestObjects(objects, const Offset(5, 5))?.id, 'high');
  });

  test('same zIndex prefers later list order', () {
    final objects = [
      _object('first', x: 0, y: 0, zIndex: 1),
      _object('second', x: 0, y: 0, zIndex: 1),
    ];
    expect(hitTestObjects(objects, const Offset(5, 5))?.id, 'second');
  });

  test('ignores invisible objects', () {
    final objects = [
      _object('hidden', x: 0, y: 0, zIndex: 9, visible: false),
      _object('shown', x: 0, y: 0, zIndex: 0),
    ];
    expect(hitTestObjects(objects, const Offset(5, 5))?.id, 'shown');
  });

  test('empty space misses', () {
    final objects = [_object('a', x: 0, y: 0)];
    expect(hitTestObjects(objects, const Offset(50, 50)), isNull);
  });

  test('locked objects are still hittable but cannot move', () {
    final locked = _object('lock', x: 0, y: 0, locked: true);
    expect(hitTestObjects([locked], const Offset(5, 5))?.id, 'lock');
    expect(objectAllowsMove(locked), isFalse);
    expect(objectAllowsMove(_object('free')), isTrue);
  });
}
