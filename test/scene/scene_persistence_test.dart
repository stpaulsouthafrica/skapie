import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('save then load round-trips the document', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_scene_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/scene.json');
    final persistence = SceneFilePersistence(file);

    final store = SceneStore(persistence: persistence);
    store.apply(
      AddNode(
        SceneNode(
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
      AddNode(
        SceneNode(id: 'n2', type: 'box', x: 0, y: 1, width: 2, height: 3),
      ),
    );
    await store.save();

    final loaded = SceneStore(persistence: persistence);
    await loaded.load();

    expect(loaded.document, store.document);
  });

  test('load with missing file yields an empty document', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_scene_');
    addTearDown(() => dir.delete(recursive: true));
    final store = SceneStore(
      persistence: SceneFilePersistence(File('${dir.path}/scene.json')),
    );

    await store.load();

    expect(store.document.nodes, isEmpty);
    expect(store.document.schemaVersion, currentSceneSchemaVersion);
  });
}
