import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/scene/scene.dart';

SceneObject _box(
  String id, {
  double x = 0,
  Map<String, Object?> props = const {},
}) {
  return SceneObject(
    id: id,
    type: 'debug.rect',
    x: x,
    y: 0,
    width: 10,
    height: 10,
    props: props,
  );
}

void main() {
  test('AddObject then RemoveObject', () {
    final store = SceneStore();
    store.apply(AddObject(_box('a')));
    store.apply(AddObject(_box('b', x: 5)));

    expect(store.document.objects.map((o) => o.id), ['a', 'b']);

    store.apply(const RemoveObject('a'));
    expect(store.document.objects.map((o) => o.id), ['b']);
  });

  test('UpdateObjectFrame and UpdateObjectProps merge', () {
    final store = SceneStore();
    store.apply(AddObject(_box('a', props: const {'keep': 1, 'old': 'x'})));

    store.apply(
      const UpdateObjectFrame(id: 'a', x: 40, y: 50, width: 80, height: 20),
    );
    var object = store.document.objects.single;
    expect(object.x, 40);
    expect(object.y, 50);
    expect(object.width, 80);
    expect(object.height, 20);

    store.apply(const UpdateObjectProps('a', {'old': 'y', 'extra': true}));
    object = store.document.objects.single;
    expect(object.props, {'keep': 1, 'old': 'y', 'extra': true});
  });

  test('UpdateObjectProps removes keys set to null', () {
    final store = SceneStore();
    store.apply(AddObject(_box('a', props: const {'keep': 1, 'gone': 2})));
    store.apply(const UpdateObjectProps('a', {'gone': null}));
    expect(store.document.objects.single.props, {'keep': 1});
  });

  test('undo/redo across ops; new apply after undo clears redo', () {
    final store = SceneStore();
    store.apply(AddObject(_box('a')));
    store.apply(AddObject(_box('b')));
    store.apply(const UpdateObjectFrame(id: 'b', x: 9));

    expect(store.document.objects, hasLength(2));
    expect(store.document.objects.last.x, 9);

    store.undo();
    expect(store.document.objects.last.x, 0);

    store.undo();
    expect(store.document.objects.map((o) => o.id), ['a']);

    store.redo();
    expect(store.document.objects.map((o) => o.id), ['a', 'b']);

    store.apply(AddObject(_box('c')));
    expect(store.canRedo, isFalse);
    store.redo();
    expect(store.document.objects.map((o) => o.id), ['a', 'b', 'c']);
  });

  test('SetObjectLocked applies, undoes, and no-ops when unchanged', () {
    final store = SceneStore();
    store.apply(AddObject(_box('a')));
    expect(store.document.objects.single.locked, isFalse);

    store.apply(const SetObjectLocked(id: 'a', locked: true));
    expect(store.document.objects.single.locked, isTrue);

    store.undo();
    expect(store.document.objects.single.locked, isFalse);

    expect(
      store.apply(const SetObjectLocked(id: 'missing', locked: true)),
      isFalse,
    );
    expect(store.apply(const SetObjectLocked(id: 'a', locked: false)), isFalse);
  });
}
