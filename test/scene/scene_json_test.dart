import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/scene/scene.dart';

SceneNode _node({
  required String id,
  String type = 'debug.rect',
  double x = 0,
  double y = 0,
  double width = 100,
  double height = 40,
  Map<String, Object?> props = const {},
}) {
  return SceneNode(
    id: id,
    type: type,
    x: x,
    y: y,
    width: width,
    height: height,
    props: props,
  );
}

void main() {
  test('JSON round-trip preserves a document with nodes and props', () {
    final original = SceneDocument(
      id: 'doc-1',
      schemaVersion: currentSceneSchemaVersion,
      camera: const SceneCameraSnapshot(offsetX: 12.5, offsetY: -4, zoom: 1.5),
      nodes: [
        _node(
          id: 'a',
          x: 10,
          y: 20,
          width: 120,
          height: 80,
          props: const {'label': 'alpha', 'count': 3, 'on': true},
        ),
        _node(
          id: 'b',
          type: 'box',
          x: -50,
          y: 8,
          width: 40,
          height: 40,
          props: const {
            'nested': {'k': 'v'},
          },
        ),
      ],
    );

    final decoded = SceneDocument.fromJson(original.toJson());

    expect(decoded, original);
    expect(decoded.schemaVersion, currentSceneSchemaVersion);
    expect(decoded.nodes, hasLength(2));
    expect(decoded.nodes[0].props['label'], 'alpha');
    expect(decoded.nodes[1].props['nested'], {'k': 'v'});
  });

  test('schemaVersion is required in JSON', () {
    expect(
      () => SceneDocument.fromJson({'id': 'doc-1', 'nodes': <Object?>[]}),
      throwsFormatException,
    );
  });

  test('schemaVersion is read from JSON', () {
    final doc = SceneDocument.fromJson({
      'id': 'doc-1',
      'schemaVersion': 1,
      'nodes': <Object?>[],
    });
    expect(doc.schemaVersion, 1);
  });

  test('unknown JSON fields are ignored (tolerant parsing)', () {
    final doc = SceneDocument.fromJson({
      'id': 'doc-1',
      'schemaVersion': 1,
      'futureTopLevel': {'ignore': true},
      'nodes': [
        {
          'id': 'n1',
          'type': 'debug.rect',
          'x': 1,
          'y': 2,
          'width': 3,
          'height': 4,
          'futureNodeField': 'nope',
        },
      ],
    });

    expect(doc.id, 'doc-1');
    expect(doc.nodes, hasLength(1));
    expect(doc.nodes.single.id, 'n1');
    expect(doc.nodes.single.x, 1);
  });
}
