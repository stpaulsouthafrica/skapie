import 'dart:convert';
import 'dart:io';

import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/registry/object_registry.dart';
import 'package:skapie/scene/scene_json_codec.dart';

class KitLoadResult {
  const KitLoadResult({
    required this.recipes,
    this.warnings = const [],
    this.errors = const [],
  });

  final List<KitRecipe> recipes;
  final List<String> warnings;
  final List<String> errors;
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
        errors: ['Cannot read kits root ${root.path}: $error'],
      );
    }
    final recipes = <KitRecipe>[];
    final warnings = <String>[];
    final errors = <String>[];
    final List<Directory> dirs;
    try {
      dirs = [
        await for (final entity in root.list())
          if (entity is Directory) entity,
      ]..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException catch (error) {
      return KitLoadResult(
        recipes: const [],
        errors: ['Cannot list kits root ${root.path}: $error'],
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
        recipes.add(parsed.recipe);
      } catch (error) {
        errors.add('Skip $folderId: $error');
      }
    }
    return KitLoadResult(recipes: recipes, warnings: warnings, errors: errors);
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
    return file;
  }
}
