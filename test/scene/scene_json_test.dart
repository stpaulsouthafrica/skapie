import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/scene/scene.dart';

SceneObject _object({
  required String id,
  String type = 'debug.rect',
  double x = 0,
  double y = 0,
  double width = 100,
  double height = 40,
  Map<String, Object?> props = const {},
}) {
  return SceneObject(
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
  test('JSON round-trip preserves a document with objects and props', () {
    final original = SceneDocument(
      id: 'doc-1',
      schemaVersion: currentSceneSchemaVersion,
      camera: const SceneCameraSnapshot(offsetX: 12.5, offsetY: -4, zoom: 1.5),
      objects: [
        _object(
          id: 'a',
          x: 10,
          y: 20,
          width: 120,
          height: 80,
          props: const {'label': 'alpha', 'count': 3, 'on': true},
        ),
        _object(
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

    final encoded = original.toJson();
    expect(encoded.containsKey('objects'), isTrue);
    expect(encoded.containsKey('nodes'), isFalse);

    final decoded = SceneDocument.fromJson(encoded);

    expect(decoded, original);
    expect(decoded.schemaVersion, currentSceneSchemaVersion);
    expect(decoded.objects, hasLength(2));
    expect(decoded.objects[0].props['label'], 'alpha');
    expect(decoded.objects[1].props['nested'], {'k': 'v'});
  });

  test('schemaVersion is required in JSON', () {
    expect(
      () => SceneDocument.fromJson({'id': 'doc-1', 'objects': <Object?>[]}),
      throwsFormatException,
    );
  });

  test('schemaVersion is read from JSON', () {
    final doc = SceneDocument.fromJson({
      'id': 'doc-1',
      'schemaVersion': 1,
      'objects': <Object?>[],
    });
    expect(doc.schemaVersion, 1);
  });

  test('unknown JSON fields are ignored (tolerant parsing)', () {
    final doc = SceneDocument.fromJson({
      'id': 'doc-1',
      'schemaVersion': 1,
      'futureTopLevel': {'ignore': true},
      'objects': [
        {
          'id': 'n1',
          'type': 'debug.rect',
          'x': 1,
          'y': 2,
          'width': 3,
          'height': 4,
          'futureObjectField': 'nope',
        },
      ],
    });

    expect(doc.id, 'doc-1');
    expect(doc.objects, hasLength(1));
    expect(doc.objects.single.id, 'n1');
    expect(doc.objects.single.x, 1);
  });

  test('legacy nodes key still loads; resave uses objects', () {
    final doc = SceneDocument.fromJson({
      'id': 'doc-1',
      'schemaVersion': 1,
      'nodes': [
        {
          'id': 'legacy',
          'type': 'debug.rect',
          'x': 8,
          'y': 9,
          'width': 10,
          'height': 11,
        },
      ],
    });

    expect(doc.schemaVersion, 1);
    expect(doc.objects, hasLength(1));
    expect(doc.objects.single.id, 'legacy');
    expect(doc.toJson().containsKey('objects'), isTrue);
    expect(doc.toJson().containsKey('nodes'), isFalse);
  });

  test('objects wins when both objects and nodes are present', () {
    final doc = SceneDocument.fromJson({
      'id': 'doc-1',
      'schemaVersion': 1,
      'objects': [
        {
          'id': 'kept',
          'type': 'debug.rect',
          'x': 1,
          'y': 1,
          'width': 1,
          'height': 1,
        },
      ],
      'nodes': [
        {
          'id': 'ignored',
          'type': 'debug.rect',
          'x': 2,
          'y': 2,
          'width': 2,
          'height': 2,
        },
      ],
    });

    expect(doc.objects.single.id, 'kept');
  });
}
