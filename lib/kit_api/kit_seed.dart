import 'dart:io';

import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/tools/world/kits.dart';

/// The starter packages copied into a fresh user shelf. The `board.*`
/// primitives are host recipes, not packages, so they are not seeded.
List<KitRecipe> starterSeedRecipes() {
  return [
    harnessLlmRecipe,
    harnessConversationRecipe,
    codingRepositoryRecipe,
    skapieExtensionsRecipe,
    for (final spec in worldToolKitSpecs) worldToolKitRecipe(spec),
  ];
}

class KitSeedResult {
  const KitSeedResult({required this.written, required this.kept});

  final List<String> written;
  final List<String> kept;
}

/// Copy the lean starter set into [root] once. A package whose folder already
/// exists is the user's copy and is never overwritten.
Future<KitSeedResult> seedStarterKits(KitPackageStore store) async {
  final written = <String>[];
  final kept = <String>[];
  for (final recipe in starterSeedRecipes()) {
    final dir = Directory('${store.root.path}/${recipe.id}');
    if (await dir.exists()) {
      kept.add(recipe.id);
      continue;
    }
    await store.write(recipe);
    written.add(recipe.id);
  }
  return KitSeedResult(written: written, kept: kept);
}

/// Ids the seed installs, for tests and docs.
Set<String> get starterSeedKitIds => {
  for (final recipe in starterSeedRecipes()) recipe.id,
};
