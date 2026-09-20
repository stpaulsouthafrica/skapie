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

  test('first save creates missing parent directories', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_scene_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/nested/skapie/scene.json');
    expect(await file.parent.exists(), isFalse);

    final store = SceneStore(persistence: SceneFilePersistence(file));
    store.apply(
      AddObject(
        SceneObject(
          id: 'a',
          type: 'debug.rect',
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      ),
    );
    await store.save();

    expect(await file.exists(), isTrue);
    expect(_decode(file)['objects'], isNotEmpty);
  });

  test(
    'legacy cwd file migrates into canonical when canonical is missing',
    () async {
      final dir = await Directory.systemTemp.createTemp('skapie_scene_');
      addTearDown(() => dir.delete(recursive: true));
      final cwd = Directory('${dir.path}/cwd');
      final canonical = File('${dir.path}/support/skapie/scene.json');
      await cwd.create(recursive: true);
      final legacy = File('${cwd.path}/.skapie/scene.json');
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('''
{
  "id": "migrated-doc",
  "schemaVersion": 1,
  "objects": [
    {
      "id": "moved",
      "type": "debug.rect",
      "x": 1,
      "y": 2,
      "width": 3,
      "height": 4
    }
  ]
}
''');

      await migrateLegacySceneIfNeeded(canonical: canonical, cwd: cwd);

      expect(await canonical.exists(), isTrue);
      final store = SceneStore(persistence: SceneFilePersistence(canonical));
      await store.load();
      expect(store.document.id, 'migrated-doc');
      expect(store.document.objects.single.id, 'moved');
    },
  );

  test('save failure is recorded and logged, not silent', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_scene_');
    addTearDown(() => dir.delete(recursive: true));
    final blocker = Directory('${dir.path}/scene.json');
    await blocker.create();
    final store = SceneStore(
      persistence: SceneFilePersistence(File(blocker.path)),
    );
    store.apply(
      AddObject(
        SceneObject(
          id: 'a',
          type: 'debug.rect',
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      ),
    );
    await store.save();
    expect(store.lastPersistenceError, isNotNull);
  });
}
