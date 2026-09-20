import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/scene/scene.dart';

SceneNode _box(
  String id, {
  double x = 0,
  Map<String, Object?> props = const {},
}) {
  return SceneNode(
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
  test('AddNode then RemoveNode', () {
    final store = SceneStore();
    store.apply(AddNode(_box('a')));
    store.apply(AddNode(_box('b', x: 5)));

    expect(store.document.nodes.map((n) => n.id), ['a', 'b']);

    store.apply(const RemoveNode('a'));
    expect(store.document.nodes.map((n) => n.id), ['b']);
  });

  test('UpdateNodeFrame and UpdateNodeProps merge', () {
    final store = SceneStore();
    store.apply(AddNode(_box('a', props: const {'keep': 1, 'old': 'x'})));

    store.apply(
      const UpdateNodeFrame(id: 'a', x: 40, y: 50, width: 80, height: 20),
    );
    var node = store.document.nodes.single;
    expect(node.x, 40);
    expect(node.y, 50);
    expect(node.width, 80);
    expect(node.height, 20);

    store.apply(const UpdateNodeProps('a', {'old': 'y', 'extra': true}));
    node = store.document.nodes.single;
    expect(node.props, {'keep': 1, 'old': 'y', 'extra': true});
  });

  test('UpdateNodeProps removes keys set to null', () {
    final store = SceneStore();
    store.apply(AddNode(_box('a', props: const {'keep': 1, 'gone': 2})));
    store.apply(const UpdateNodeProps('a', {'gone': null}));
    expect(store.document.nodes.single.props, {'keep': 1});
  });

  test('undo/redo across ops; new apply after undo clears redo', () {
    final store = SceneStore();
    store.apply(AddNode(_box('a')));
    store.apply(AddNode(_box('b')));
    store.apply(const UpdateNodeFrame(id: 'b', x: 9));

    expect(store.document.nodes, hasLength(2));
    expect(store.document.nodes.last.x, 9);

    store.undo();
    expect(store.document.nodes.last.x, 0);

    store.undo();
    expect(store.document.nodes.map((n) => n.id), ['a']);

    store.redo();
    expect(store.document.nodes.map((n) => n.id), ['a', 'b']);

    store.apply(AddNode(_box('c')));
    expect(store.canRedo, isFalse);
    store.redo();
    expect(store.document.nodes.map((n) => n.id), ['a', 'b', 'c']);
  });
}
