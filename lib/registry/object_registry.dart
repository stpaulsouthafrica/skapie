import 'package:flutter/widgets.dart';
import 'package:skapie/registry/object_type.dart';
import 'package:skapie/registry/unknown_object_placeholder.dart';
import 'package:skapie/scene/scene_object.dart';

/// Maps `SceneObject.type` to a builder. Does not mutate the scene.
class ObjectRegistry {
  final Map<String, ObjectType> _types = {};

  void register(ObjectType type) {
    if (_types.containsKey(type.typeId)) {
      throw StateError('Duplicate typeId: ${type.typeId}');
    }
    _types[type.typeId] = type;
  }

  ObjectType? get(String typeId) => _types[typeId];

  List<ObjectType> list() => List.unmodifiable(_types.values);

  Widget build(
    BuildContext context,
    SceneObject object, {
    RegistryBuildContext ctx = const RegistryBuildContext(),
  }) {
    final type = _types[object.type];
    if (type == null) {
      return UnknownObjectPlaceholder(typeId: object.type);
    }
    try {
      return type.builder(context, object, ctx);
    } catch (error, stack) {
      debugPrint(
        'Skapie registry builder failed for ${object.type}: $error\n$stack',
      );
      return UnknownObjectPlaceholder(typeId: object.type);
    }
  }
}
