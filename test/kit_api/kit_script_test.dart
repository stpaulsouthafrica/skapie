import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/kit_api/kit_script.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

class _AllowRead implements RepositoryPermission {
  const _AllowRead();

  @override
  Future<String?> chooseDirectory() async => null;

  @override
  Future<bool> canRead(String path) async => true;
}

void main() {
  test('a copied kit folder works on the next load', () async {
    final root = await Directory.systemTemp.createTemp('skapie-kit-copy');
    final repo = await Directory.systemTemp.createTemp('skapie-kit-repo');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => repo.delete(recursive: true));
    await File('${repo.path}/hello.txt').writeAsString('hello');
    final source = Directory('kits/tools.read');
    final dest = Directory('${root.path}/tools.read');
    await dest.create();
    await File('${source.path}/kit.json').copy('${dest.path}/kit.json');
    await File('${source.path}/kit.dart').copy('${dest.path}/kit.dart');

    final registry = createBuiltinRegistry();
    final packages = KitPackageStore(root: root, registry: registry);
    final api = createAppKitApi(
      store: SceneStore(),
      registry: registry,
      packages: packages,
    );
    await api.reloadPackages();

    final tool = api.packageTool('read');
    expect(tool, isNotNull);
    final result = await tool!.toAgentTool(
      KitToolBinding(readPath: repo.path, readPermission: const _AllowRead()),
    ).run({'action': 'read', 'path': 'hello.txt'});
    expect(jsonEncode(result), contains('hello'));
  });
}
