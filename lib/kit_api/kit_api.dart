import 'dart:ui';

import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

const String demoNoteCardKitId = 'demo.note-card';

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

/// High-level scene mutations. Always wraps [SceneStore.apply]. In-memory kits only.
class KitApi {
  KitApi({required this.store, required this.registry});

  final SceneStore store;
  final ObjectRegistry registry;
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

KitApi createAppKitApi({required SceneStore store, ObjectRegistry? registry}) {
  final api = KitApi(
    store: store,
    registry: registry ?? createBuiltinRegistry(),
  );
  api.registerKit(demoNoteCardRecipe);
  return api;
}
