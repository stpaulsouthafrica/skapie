import 'dart:ui';

import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/world/kits.dart';

const String demoNoteCardKitId = 'demo.note-card';
const String harnessLlmKitId = 'harness.llm';
const String harnessSystemPromptKitId = 'harness.system-prompt';
const String harnessToolsKitId = 'harness.tools';
const String skapieKitProp = 'skapieKit';
const String skapieRoleProp = 'skapieRole';
const String attachedToProp = 'attachedTo';
const String harnessToolsRoster =
    'list_kits, get_kit, instantiate_kit, add_object, remove_object, update_frame, update_props, set_locked, save_kit, reload_packages, register_kit';

Size defaultObjectSize(String typeId) {
  return switch (typeId) {
    boxTypeId => const Size(160, 100),
    textTypeId => const Size(220, 48),
    buttonTypeId => const Size(140, 40),
    debugRectType => const Size(120, 80),
    _ => const Size(120, 80),
  };
}

class KitObjectSpec {
  const KitObjectSpec({
    required this.typeId,
    required this.x,
    required this.y,
    this.width,
    this.height,
    this.props = const {},
  });

  final String typeId;
  final double x;
  final double y;
  final double? width;
  final double? height;
  final Map<String, Object?> props;
}

class KitRecipe {
  const KitRecipe({
    required this.id,
    required this.displayName,
    required this.objects,
  });

  final String id;
  final String displayName;
  final List<KitObjectSpec> objects;
}

const KitRecipe demoNoteCardRecipe = KitRecipe(
  id: demoNoteCardKitId,
  displayName: 'Note card',
  objects: [
    KitObjectSpec(typeId: boxTypeId, x: 0, y: 0, width: 200, height: 88),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 16,
      width: 176,
      height: 56,
      props: {'content': 'Note'},
    ),
  ],
);

const KitRecipe harnessLlmRecipe = KitRecipe(
  id: harnessLlmKitId,
  displayName: 'LLM',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 320,
      height: 260,
      props: {skapieKitProp: harnessLlmKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 12,
      width: 296,
      height: 236,
      props: {
        'content': 'Needs input\n\nInput\n\nOutput\n\nTools: none',
        'fontSize': 14,
        'prompt': '',
        'reply': '',
        'error': '',
        'model': '',
        'provider': '',
        'surface': '',
        skapieKitProp: harnessLlmKitId,
        skapieRoleProp: 'body',
      },
    ),
  ],
);

const KitRecipe harnessSystemPromptRecipe = KitRecipe(
  id: harnessSystemPromptKitId,
  displayName: 'System prompt',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 280,
      height: 140,
      props: {skapieKitProp: harnessSystemPromptKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 16,
      width: 256,
      height: 108,
      props: {
        'content': 'System prompt',
        'fontSize': 14,
        attachedToProp: '',
        skapieKitProp: harnessSystemPromptKitId,
        skapieRoleProp: 'prompt',
      },
    ),
  ],
);

const KitRecipe harnessToolsRecipe = KitRecipe(
  id: harnessToolsKitId,
  displayName: 'Tools',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 280,
      height: 180,
      props: {skapieKitProp: harnessToolsKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 16,
      width: 256,
      height: 148,
      props: {
        'content': 'Kit tools (stub)\n\n$harnessToolsRoster',
        'fontSize': 14,
        'toolNames': harnessToolsRoster,
        attachedToProp: '',
        skapieKitProp: harnessToolsKitId,
        skapieRoleProp: 'tools',
      },
    ),
  ],
);

/// High-level scene mutations. Always wraps [SceneStore.apply].
///
/// [registerKit] is ephemeral (in-memory kit recipe). Saved kit packages under `kits/` are
/// the durable shelf; [reloadPackages] loads them and **disk replaces memory**.
class KitApi {
  KitApi({required this.store, required this.registry, this.packages});

  final SceneStore store;
  final ObjectRegistry registry;
  final KitPackageStore? packages;
  void Function(String message)? log;
  final Map<String, KitRecipe> _kits = {};

  String addObject({
    required String typeId,
    double x = 0,
    double y = 0,
    double? width,
    double? height,
    Map<String, Object?> props = const {},
  }) {
    final type = registry.get(typeId);
    if (type == null) {
      throw ArgumentError('Unknown typeId: $typeId');
    }
    final size = defaultObjectSize(typeId);
    final merged = Map<String, Object?>.of(type.defaultProps)..addAll(props);
    final id = newSceneId('o');
    store.apply(
      AddObject(
        SceneObject(
          id: id,
          type: typeId,
          x: x,
          y: y,
          width: width ?? size.width,
          height: height ?? size.height,
          props: Map<String, Object?>.unmodifiable(merged),
        ),
      ),
    );
    return id;
  }

  void removeObject(String id) {
    store.apply(RemoveObject(id));
  }

  void updateFrame({
    required String id,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) {
    store.apply(
      UpdateObjectFrame(
        id: id,
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: rotation,
      ),
    );
  }

  void updateProps(String id, Map<String, Object?> patch) {
    store.apply(UpdateObjectProps(id, patch));
  }

  void setLocked(String id, bool locked) {
    store.apply(SetObjectLocked(id: id, locked: locked));
  }

  void registerKit(KitRecipe recipe) {
    if (_kits.containsKey(recipe.id)) {
      throw StateError('Duplicate kit id: ${recipe.id}');
    }
    _kits[recipe.id] = recipe;
  }

  KitRecipe? getKit(String kitId) => _kits[kitId];

  List<KitRecipe> listKits() => List.unmodifiable(_kits.values);

  /// Scan the kits root and register each package. Disk replaces in-memory
  /// kit recipes with the same id.
  Future<void> reloadPackages() async {
    final store = packages;
    if (store == null) {
      return;
    }
    final loaded = await store.loadAll();
    for (final warning in loaded.warnings) {
      log?.call(warning);
    }
    for (final error in loaded.errors) {
      log?.call(error);
    }
    for (final recipe in loaded.recipes) {
      if (_kits.containsKey(recipe.id)) {
        log?.call('Disk package ${recipe.id} replaces in-memory kit recipe');
      }
      _kits[recipe.id] = recipe;
    }
    log?.call(
      'Loaded ${loaded.recipes.length} kit package(s) from ${store.root.absolute.path}',
    );
  }

  /// Write `kits/<id>/kit.json`, then register/update the in-memory kit recipe.
  Future<void> saveKit(KitRecipe recipe) async {
    final store = packages;
    if (store == null) {
      throw StateError('No kit package store');
    }
    await store.write(recipe);
    _kits[recipe.id] = recipe;
  }

  /// Validate every spec type, then apply. N objects = N undo steps.
  List<String> instantiate(String kitId, {required Offset origin}) {
    final recipe = _kits[kitId];
    if (recipe == null) {
      throw ArgumentError('Unknown kit: $kitId');
    }
    for (final spec in recipe.objects) {
      if (registry.get(spec.typeId) == null) {
        throw ArgumentError('Unknown typeId: ${spec.typeId}');
      }
    }
    return [
      for (final spec in recipe.objects)
        addObject(
          typeId: spec.typeId,
          x: origin.dx + spec.x,
          y: origin.dy + spec.y,
          width: spec.width,
          height: spec.height,
          props: spec.props,
        ),
    ];
  }
}

KitApi createAppKitApi({
  required SceneStore store,
  ObjectRegistry? registry,
  KitPackageStore? packages,
}) {
  final api = KitApi(
    store: store,
    registry: registry ?? createBuiltinRegistry(),
    packages: packages,
  );
  api.registerKit(demoNoteCardRecipe);
  api.registerKit(harnessLlmRecipe);
  api.registerKit(harnessSystemPromptRecipe);
  api.registerKit(harnessToolsRecipe);
  registerWorldToolKits(api);
  return api;
}
