import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/scene/scene.dart';

Map<String, Object?> _decode(File file) {
  return Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map);
}

void main() {
  test('save then load round-trips the document', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_scene_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/scene.json');
    final persistence = SceneFilePersistence(file);

    final store = SceneStore(persistence: persistence);
    store.apply(
      AddObject(
        SceneObject(
          id: 'n1',
          type: 'debug.rect',
          x: 3,
          y: 4,
          width: 5,
          height: 6,
          props: const {'p': 'q'},
        ),
      ),
    );
    store.apply(
      AddObject(
        SceneObject(id: 'n2', type: 'box', x: 0, y: 1, width: 2, height: 3),
      ),
    );
    await store.save();

    final loaded = SceneStore(persistence: persistence);
    await loaded.load();

    expect(loaded.document, store.document);
    final saved = _decode(file);
    expect(saved.containsKey('objects'), isTrue);
    expect(saved.containsKey('nodes'), isFalse);
  });

  test('load with missing file yields an empty document', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_scene_');
    addTearDown(() => dir.delete(recursive: true));
    final store = SceneStore(
      persistence: SceneFilePersistence(File('${dir.path}/scene.json')),
    );

    await store.load();

    expect(store.document.objects, isEmpty);
    expect(store.document.schemaVersion, currentSceneSchemaVersion);
  });

  test('legacy scene.json with nodes still loads', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_scene_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/scene.json');
    await file.writeAsString('''
{
  "id": "legacy-doc",
  "schemaVersion": 1,
  "nodes": [
    {
      "id": "from-nodes",
      "type": "debug.rect",
      "x": 1,
      "y": 2,
      "width": 3,
      "height": 4
    }
  ]
}
''');

    final store = SceneStore(persistence: SceneFilePersistence(file));
    await store.load();

    expect(store.document.objects.single.id, 'from-nodes');
    await store.save();
    final saved = _decode(file);
    expect(saved.containsKey('objects'), isTrue);
    expect(saved.containsKey('nodes'), isFalse);
  });
}
