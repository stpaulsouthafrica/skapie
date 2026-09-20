import 'package:flutter/widgets.dart';
import 'package:skapie/scene/scene_object.dart';

class RegistryBuildContext {
  const RegistryBuildContext({this.zoom = 1});

  final double zoom;
}

typedef SceneObjectBuilder = Widget Function(
  BuildContext context,
  SceneObject object,
  RegistryBuildContext ctx,
);

class ObjectType {
  const ObjectType({
    required this.typeId,
    required this.displayName,
    required this.defaultProps,
    required this.builder,
  });

  final String typeId;
  final String displayName;
  final Map<String, Object?> defaultProps;
  final SceneObjectBuilder builder;
}
