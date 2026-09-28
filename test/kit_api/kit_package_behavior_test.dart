import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/kit_api/kit_package_ports.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  final registry = createBuiltinRegistry();

  test('package ports parse, round-trip, and reject unknown values', () {
    final ports = parseKitPackagePorts([
      {'id': 'out', 'value': 'text', 'flow': 'output', 'label': 'Docs'},
    ]);
    expect(ports, hasLength(1));
    expect(ports.first.isOutput, isTrue);
    final json = kitPackagePortsToJson(ports);
    expect(parseKitPackagePorts(json), hasLength(1));
    expect(
      () => parseKitPackagePorts([
        {'id': 'x', 'value': 'telepathy', 'flow': 'output'},
      ]),
      throwsFormatException,
    );
    expect(
      () => parseKitPackagePorts([
        {'id': 'x', 'value': 'repository', 'flow': 'input'},
      ]),
      throwsFormatException,
    );
  });

  test('saveKit writes asset files next to kit.json', () async {
    final root = await Directory.systemTemp.createTemp('skapie_behavior_');
    addTearDown(() => root.delete(recursive: true));
    final api = KitApi(
      store: SceneStore(),
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );
    await api.saveKit(
      const KitRecipe(
        id: 'demo.asset',
        displayName: 'Asset',
        objects: [],
        assets: {'notes/check.txt': 'Check the diff.'},
      ),
    );
    final asset = File('${root.path}/demo.asset/notes/check.txt');
    expect(await asset.readAsString(), 'Check the diff.');
    final reloaded = KitPackageStore(root: root, registry: registry);
    final loaded = await reloaded.loadAll();
    expect(loaded.recipes.single.assets['notes/check.txt'], 'Check the diff.');
  });

  test('kit.json assets must be relative and safe', () {
    expect(
      () => parseKitPackageJson({
        'schemaVersion': 1,
        'id': 'demo.bad',
        'displayName': 'Bad',
        'objects': <Object?>[],
        'assets': ['../secret.txt'],
      }, folderId: 'demo.bad'),
      throwsFormatException,
    );
  });

  test('instantiate stamps package ports and loads asset content', () async {
    final root = await Directory.systemTemp.createTemp('skapie_behavior_');
    addTearDown(() => root.delete(recursive: true));
    final dir = Directory('${root.path}/demo.checklist');
    await dir.create(recursive: true);
    await File('${dir.path}/checklist.txt').writeAsString('Check the diff.');
    await File('${dir.path}/kit.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'id': 'demo.checklist',
        'displayName': 'Checklist',
        'ports': [
          {'id': 'out', 'value': 'text', 'flow': 'output', 'label': 'Docs'},
        ],
        'assets': ['checklist.txt'],
        'objects': [
          {
            'typeId': 'box',
            'x': 0,
            'y': 0,
            'width': 220,
            'height': 120,
            'props': {skapieKitProp: 'demo.checklist', skapieRoleProp: 'frame'},
          },
          {
            'typeId': 'text',
            'x': 12,
            'y': 40,
            'width': 196,
            'height': 48,
            'props': {
              skapieKitProp: 'demo.checklist',
              skapieRoleProp: 'body',
              'contentRef': 'checklist.txt',
            },
          },
        ],
      }),
    );

    final api = createAppKitApi(
      store: SceneStore(),
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );
    await api.reloadPackages();
    final recipe = api.getKit('demo.checklist')!;
    expect(recipe.assets['checklist.txt'], 'Check the diff.');

    final ids = api.instantiate('demo.checklist', origin: Offset.zero);
    final frame = api.store.document.objectById(ids.first)!;
    expect(frame.props[packagePortsProp], isA<List>());
    expect(kitPortSpecsFor(frame).single.label, 'Docs');
    final body = api.store.document.objectById(ids.last)!;
    expect(body.props['content'], 'Check the diff.');
  });

  test('a package text kit cabled to Context feeds the request', () async {
    final root = await Directory.systemTemp.createTemp('skapie_behavior_');
    addTearDown(() => root.delete(recursive: true));
    final dir = Directory('${root.path}/demo.checklist');
    await dir.create(recursive: true);
    await File('${dir.path}/checklist.txt').writeAsString('Check the diff.');
    await File('${dir.path}/kit.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'id': 'demo.checklist',
        'displayName': 'Checklist',
        'ports': [
          {'id': 'out', 'value': 'text', 'flow': 'output', 'label': 'Docs'},
        ],
        'assets': ['checklist.txt'],
        'objects': [
          {
            'typeId': 'box',
            'x': 0,
            'y': 0,
            'width': 220,
            'height': 120,
            'props': {skapieKitProp: 'demo.checklist', skapieRoleProp: 'frame'},
          },
          {
            'typeId': 'text',
            'x': 12,
            'y': 40,
            'width': 196,
            'height': 48,
            'props': {
              skapieKitProp: 'demo.checklist',
              skapieRoleProp: 'body',
              'contentRef': 'checklist.txt',
            },
          },
        ],
      }),
    );

    final api = createAppKitApi(
      store: SceneStore(),
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );
    await api.reloadPackages();
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final checklist = api.instantiate(
      'demo.checklist',
      origin: const Offset(-400, 0),
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: checklist.first,
      llmBodyId: llm.last,
      port: llmContextPort,
    );

    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'Do it',
    );
    expect(
      assembly.itemsFor(ContextLayer.instructions).map((item) => item.text),
      contains('Check the diff.'),
    );
  });
}
