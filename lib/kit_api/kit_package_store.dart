import 'dart:convert';
import 'dart:io';

import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/registry/object_registry.dart';
import 'package:skapie/scene/scene_json_codec.dart';

class KitLoadFailure {
  const KitLoadFailure({required this.id, required this.message});

  final String id;
  final String message;

  String get text => 'Skip $id: $message';
}

class KitLoadResult {
  const KitLoadResult({
    required this.recipes,
    this.warnings = const [],
    this.failures = const [],
  });

  final List<KitRecipe> recipes;
  final List<String> warnings;
  final List<KitLoadFailure> failures;
}

class KitPackageStore {
  KitPackageStore({required this.root, required this.registry});

  final Directory root;
  final ObjectRegistry registry;

  Future<KitLoadResult> loadAll() async {
    try {
      if (!await root.exists()) {
        return const KitLoadResult(recipes: []);
      }
    } on FileSystemException catch (error) {
      return KitLoadResult(
        recipes: const [],
        failures: [
          KitLoadFailure(
            id: 'kits-root',
            message: 'Cannot read kits root ${root.path}: $error',
          ),
        ],
      );
    }
    final recipes = <KitRecipe>[];
    final warnings = <String>[];
    final failures = <KitLoadFailure>[];
    final List<Directory> dirs;
    try {
      dirs = [
        await for (final entity in root.list())
          if (entity is Directory) entity,
      ]..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException catch (error) {
      return KitLoadResult(
        recipes: const [],
        failures: [
          KitLoadFailure(
            id: 'kits-root',
            message: 'Cannot list kits root ${root.path}: $error',
          ),
        ],
      );
    }

    for (final dir in dirs) {
      final folderId = dir.uri.pathSegments.where((p) => p.isNotEmpty).last;
      final file = File('${dir.path}/kit.json');
      if (!await file.exists()) {
        continue;
      }
      try {
        final decoded = jsonDecode(await file.readAsString());
        final parsed = parseKitPackageJson(
          asJsonMap(decoded, 'kit.json'),
          folderId: folderId,
          registry: registry,
        );
        if (parsed.capabilityWarning != null) {
          warnings.add(parsed.capabilityWarning!);
        }
        final assets = await _loadAssets(dir, folderId, parsed, warnings);
        recipes.add(parsed.recipe.copyWith(assets: assets));
      } catch (error) {
        failures.add(KitLoadFailure(id: folderId, message: '$error'));
      }
    }
    return KitLoadResult(
      recipes: recipes,
      warnings: warnings,
      failures: failures,
    );
  }

  Future<Map<String, String>> _loadAssets(
    Directory dir,
    String folderId,
    ParsedKitPackage parsed,
    List<String> warnings,
  ) async {
    final assets = <String, String>{};
    for (final path in parsed.assetPaths) {
      final file = File('${dir.path}/$path');
      try {
        if (!await file.exists()) {
          warnings.add('Kit $folderId is missing asset: $path');
          continue;
        }
        assets[path] = await file.readAsString();
      } on FileSystemException catch (error) {
        warnings.add('Kit $folderId could not read asset $path: $error');
      }
    }
    return assets;
  }

  Future<File> write(KitRecipe recipe) async {
    if (!isValidKitId(recipe.id)) {
      throw ArgumentError('Invalid kit id: ${recipe.id}');
    }
    for (final object in recipe.objects) {
      if (registry.get(object.typeId) == null) {
        throw ArgumentError('Unknown typeId: ${object.typeId}');
      }
    }
    final dir = Directory('${root.path}/${recipe.id}');
    await dir.create(recursive: true);
    final file = File('${dir.path}/kit.json');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(kitPackageToJson(packageFromRecipe(recipe)))}\n',
    );
    for (final entry in recipe.assets.entries) {
      if (!_isSafeAssetPath(entry.key)) {
        throw ArgumentError('Invalid asset path: ${entry.key}');
      }
      final asset = File('${dir.path}/${entry.key}');
      await asset.parent.create(recursive: true);
      await asset.writeAsString(entry.value);
    }
    return file;
  }
}

bool _isSafeAssetPath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains('..')) {
    return false;
  }
  return !path.contains('\\');
}
