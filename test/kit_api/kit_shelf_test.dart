import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/starter_set.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/kit_api/kit_path.dart';
import 'package:skapie/kit_api/kit_seed.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late Directory appSupport;
  late Directory home;

  setUp(() async {
    appSupport = await Directory.systemTemp.createTemp('skapie_appsupport_');
    home = await Directory.systemTemp.createTemp('skapie_home_');
    addTearDown(() => appSupport.delete(recursive: true));
    addTearDown(() => home.delete(recursive: true));
  });

  group('13.1.1 default root', () {
    test('resolves to ~/.skapie/kits when nothing overrides', () {
      final resolved = resolveKitsRoot(
        homeDirectory: home,
        appSupportDirectory: appSupport,
      );
      expect(resolved.source, 'user');
      expect(resolved.directory.path, '${home.path}/.skapie/kits');
      expect(resolved.warning, isNull);
    });
  });

  group('13.1.3 override', () {
    test('absolute SKAPIE_KITS_ROOT wins over the home shelf', () {
      final shelf = Directory('${home.path}/custom');
      final resolved = resolveKitsRoot(
        envPath: shelf.path,
        homeDirectory: home,
        appSupportDirectory: appSupport,
      );
      expect(resolved.source, 'override');
      expect(resolved.directory.path, shelf.path);
    });

    test('relative override warns and falls back to the user shelf', () {
      final resolved = resolveKitsRoot(
        dartDefinePath: 'relative/kits',
        homeDirectory: home,
        appSupportDirectory: appSupport,
      );
      expect(resolved.source, 'user');
      expect(resolved.warning, isNotNull);
      expect(resolved.directory.path, '${home.path}/.skapie/kits');
    });

    test('project root reads <root>/kits for development', () {
      final resolved = resolveKitsRoot(
        projectRoot: home.path,
        homeDirectory: home,
        appSupportDirectory: appSupport,
      );
      expect(resolved.source, 'project');
      expect(resolved.directory.path, '${home.path}/kits');
    });
  });

  group('13.1.2 seed once', () {
    test('seed ids match the starter set minus host board recipes', () {
      expect(
        starterSeedKitIds,
        unorderedEquals(
          starterKitIds.difference({
            boardTextKitId,
            boardBoxKitId,
            boardButtonKitId,
          }),
        ),
      );
    });

    test('seeds the lean starter set and preserves edits', () async {
      final root = Directory('${home.path}/.skapie/kits');
      await root.create(recursive: true);
      final registry = createBuiltinRegistry();
      final store = KitPackageStore(root: root, registry: registry);

      final first = await seedStarterKits(store);
      expect(first.written, unorderedEquals(starterSeedKitIds));
      for (final id in starterSeedKitIds) {
        expect(File('${root.path}/$id/kit.json').existsSync(), isTrue, reason: id);
      }

      final edited = File('${root.path}/harness.llm/kit.json');
      await edited.writeAsString('{"edited": true}');

      final second = await seedStarterKits(store);
      expect(second.written, isEmpty);
      expect(second.kept, unorderedEquals(starterSeedKitIds));
      expect(await edited.readAsString(), '{"edited": true}');
    });

    test('a seeded package reloads and can be placed', () async {
      final root = Directory('${home.path}/.skapie/kits');
      await root.create(recursive: true);
      final registry = createBuiltinRegistry();
      final store = KitPackageStore(root: root, registry: registry);
      await seedStarterKits(store);

      final api = createAppKitApi(
        store: SceneStore(),
        registry: registry,
        packages: store,
      );
      await api.reloadPackages();
      expect(api.getKit('harness.llm'), isNotNull);

      final ids = api.instantiate('harness.llm', origin: Offset.zero);
      expect(ids, isNotEmpty);
    });
  });
}
