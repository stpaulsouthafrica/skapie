import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/kit_api/kit_path.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late ObjectRegistry registry;

  setUp(() {
    registry = createBuiltinRegistry();
  });

  test('kit.json round-trips to KitRecipe', () {
    final parsed = parseKitPackageJson(
      harnessLlmJson,
      folderId: harnessLlmKitId,
    );
    expect(parsed.recipe.id, harnessLlmKitId);
    expect(parsed.recipe.displayName, 'LLM');
    expect(parsed.recipe.objects, hasLength(2));
    expect(parsed.recipe.objects[0].typeId, 'box');
    expect(parsed.recipe.objects[1].props['content'], contains('Input'));
    expect(parsed.schemaVersion, 1);

    final encoded = kitPackageToJson(parsed);
    final again = parseKitPackageJson(encoded, folderId: harnessLlmKitId);
    expect(again.recipe.id, parsed.recipe.id);
    expect(again.recipe.objects[1].x, 12);
    expect(again.recipe.objects[1].height, 176);
  });

  test('harness kit packages parse as real recipes', () {
    final llm = parseKitPackageJson(harnessLlmJson, folderId: harnessLlmKitId);
    expect(llm.recipe.displayName, 'LLM');
    expect(
      llm.recipe.objects.any((object) => object.props['skapieRole'] == 'body'),
      isTrue,
    );

  });

  test('createAppKitApi registers the lean starter shelf', () {
    final api = createAppKitApi(store: SceneStore());
    expect(api.getKit(harnessLlmKitId), isNotNull);
    expect(api.getKit(harnessConversationKitId), isNotNull);
    expect(api.getKit(codingRepositoryKitId), isNotNull);
    expect(api.getKit(skapieExtensionsKitId), isNotNull);
    for (final name in ['read', 'write', 'edit', 'shell']) {
      expect(api.getKit('tools.$name'), isNotNull, reason: name);
    }
    expect(api.getKit('tools.list_kits'), isNull);
    expect(api.getKit('harness.run_control'), isNull);
  });

  test('rejects missing schemaVersion', () {
    expect(
      () => parseKitPackageJson(const {
        'id': 'demo.x',
        'displayName': 'X',
        'objects': [],
      }, folderId: 'demo.x'),
      throwsFormatException,
    );
  });

  test('rejects id–folder mismatch', () {
    expect(
      () => parseKitPackageJson(const {
        'schemaVersion': 1,
        'id': 'demo.a',
        'displayName': 'A',
        'objects': [],
      }, folderId: 'demo.b'),
      throwsFormatException,
    );
  });

  test('rejects unknown typeId in objects', () {
    expect(
      () => parseKitPackageJson(
        const {
          'schemaVersion': 1,
          'id': 'demo.x',
          'displayName': 'X',
          'objects': [
            {'typeId': 'nope.widget', 'x': 0, 'y': 0},
          ],
        },
        folderId: 'demo.x',
        registry: registry,
      ),
      throwsFormatException,
    );
  });

  test('non-empty capabilities still parse objects and set warning', () {
    final parsed = parseKitPackageJson(
      const {
        'schemaVersion': 1,
        'id': 'demo.x',
        'displayName': 'X',
        'capabilities': ['live'],
        'objects': [
          {'typeId': 'box', 'x': 0, 'y': 0},
        ],
      },
      folderId: 'demo.x',
      registry: registry,
    );
    expect(parsed.capabilities, ['live']);
    expect(parsed.capabilityWarning, isNotNull);
    expect(parsed.recipe.objects.single.typeId, 'box');
  });

  test('loadAll registers packages from a temp directory', () async {
    final root = await Directory.systemTemp.createTemp('skapie_kits_');
    addTearDown(() => root.delete(recursive: true));
    await _writePackage(root, 'demo.one', {
      'schemaVersion': 1,
      'id': 'demo.one',
      'displayName': 'One',
      'objects': [
        {'typeId': 'box', 'x': 1, 'y': 2, 'width': 10, 'height': 10},
      ],
    });
    await _writePackage(root, 'demo.two', {
      'schemaVersion': 1,
      'id': 'demo.two',
      'displayName': 'Two',
      'objects': [
        {
          'typeId': 'text',
          'x': 0,
          'y': 0,
          'props': {'content': 'hi'},
        },
      ],
    });

    final store = KitPackageStore(root: root, registry: registry);
    final loaded = await store.loadAll();
    expect(loaded.recipes.map((r) => r.id), ['demo.one', 'demo.two']);
  });

  test('saveKit writes folder and reload sees it', () async {
    final root = await Directory.systemTemp.createTemp('skapie_kits_');
    addTearDown(() => root.delete(recursive: true));
    final scene = SceneStore();
    final api = KitApi(
      store: scene,
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );

    await api.saveKit(
      const KitRecipe(
        id: 'demo.saved',
        displayName: 'Saved',
        objects: [
          KitObjectSpec(typeId: 'box', x: 0, y: 0, width: 40, height: 20),
        ],
      ),
    );

    expect(File('${root.path}/demo.saved/kit.json').existsSync(), isTrue);
    expect(api.getKit('demo.saved')?.displayName, 'Saved');

    final fresh = KitApi(
      store: SceneStore(),
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );
    await fresh.reloadPackages();
    expect(fresh.getKit('demo.saved')?.objects.single.typeId, 'box');
  });

  test('disk load replaces in-memory recipe for the same id', () async {
    final root = await Directory.systemTemp.createTemp('skapie_kits_');
    addTearDown(() => root.delete(recursive: true));
    await _writePackage(root, 'demo.note-card', {
      'schemaVersion': 1,
      'id': 'demo.note-card',
      'displayName': 'From disk',
      'objects': [
        {
          'typeId': 'button',
          'x': 0,
          'y': 0,
          'props': {'label': 'Disk'},
        },
      ],
    });

    final api = KitApi(
      store: SceneStore(),
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );
    api.registerKit(
      const KitRecipe(
        id: 'demo.note-card',
        displayName: 'Note card',
        objects: [
          KitObjectSpec(typeId: 'button', x: 0, y: 0, props: {'label': 'Memory'}),
        ],
      ),
    );
    expect(api.getKit('demo.note-card')!.displayName, 'Note card');

    final logs = <String>[];
    api.log = logs.add;
    await api.reloadPackages();
    expect(api.getKit('demo.note-card')!.displayName, 'From disk');
    expect(api.getKit('demo.note-card')!.objects.single.typeId, 'button');
    expect(logs.join('\n'), contains('replaces'));
  });

  test('instantiate of a disk-loaded kit validate-then-apply', () async {
    final root = await Directory.systemTemp.createTemp('skapie_kits_');
    addTearDown(() => root.delete(recursive: true));
    await _writePackage(root, 'demo.pair', {
      'schemaVersion': 1,
      'id': 'demo.pair',
      'displayName': 'Pair',
      'objects': [
        {'typeId': 'box', 'x': 0, 'y': 0, 'width': 40, 'height': 20},
        {
          'typeId': 'text',
          'x': 4,
          'y': 2,
          'width': 30,
          'height': 10,
          'props': {'content': 'hi'},
        },
      ],
    });

    final scene = SceneStore();
    final api = KitApi(
      store: scene,
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );
    await api.reloadPackages();
    api.instantiate('demo.pair', origin: const Offset(100, 50));
    expect(scene.document.objects.map((o) => o.type), ['box', 'text']);
    expect(scene.document.objects[1].x, 104);
  });

  test('relative kits root override is rejected', () {
    final home = Directory.systemTemp;
    final resolved = resolveKitsRoot(
      dartDefinePath: 'relative/kits',
      homeDirectory: home,
      appSupportDirectory: home,
    );
    expect(resolved.warning, isNotNull);
    expect(resolved.source, 'user');
    expect(resolved.directory.path, contains('skapie/kits'));
  });
}

Future<void> _writePackage(
  Directory root,
  String id,
  Map<String, Object?> json,
) async {
  final dir = Directory('${root.path}/$id');
  await dir.create(recursive: true);
  await File('${dir.path}/kit.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
}
