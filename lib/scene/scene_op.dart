import 'package:skapie/scene/scene_document.dart';
import 'package:skapie/scene/scene_object.dart';

/// The only scene mutations. Applied by [SceneStore.apply].
sealed class SceneOp {
  const SceneOp();

  SceneDocument apply(SceneDocument document);
}

final class AddObject extends SceneOp {
  const AddObject(this.object);

  final SceneObject object;

  @override
  SceneDocument apply(SceneDocument document) {
    if (document.objectById(object.id) != null) {
      return document;
    }
    return document.copyWith(objects: [...document.objects, object]);
  }
}

final class RemoveObject extends SceneOp {
  const RemoveObject(this.id);

  final String id;

  @override
  SceneDocument apply(SceneDocument document) {
    if (document.objectById(id) == null) {
      return document;
    }
    return document.copyWith(
      objects: [
        for (final object in document.objects)
          if (object.id != id) object,
      ],
    );
  }
}

final class UpdateObjectFrame extends SceneOp {
  const UpdateObjectFrame({
    required this.id,
    this.x,
    this.y,
    this.width,
    this.height,
    this.rotation,
  });

  final String id;
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  final double? rotation;

  @override
  SceneDocument apply(SceneDocument document) {
    final current = document.objectById(id);
    if (current == null) {
      return document;
    }
    final next = current.copyWith(
      x: x,
      y: y,
      width: width,
      height: height,
      rotation: rotation,
    );
    if (next == current) {
      return document;
    }
    return document.copyWith(
      objects: [
        for (final object in document.objects)
          if (object.id == id) next else object,
      ],
    );
  }
}

/// Shallow-merge [patch] into the scene object's props.
///
/// Keys with a `null` value are removed. Other existing keys are kept.
final class UpdateObjectProps extends SceneOp {
  const UpdateObjectProps(this.id, this.patch);

  final String id;
  final Map<String, Object?> patch;

  @override
  SceneDocument apply(SceneDocument document) {
    final current = document.objectById(id);
    if (current == null) {
      return document;
    }
    final props = Map<String, Object?>.from(current.props);
    for (final entry in patch.entries) {
      if (entry.value == null) {
        props.remove(entry.key);
      } else {
        props[entry.key] = entry.value;
      }
    }
    final next = current.copyWith(
      props: Map<String, Object?>.unmodifiable(props),
    );
    if (next == current) {
      return document;
    }
    return document.copyWith(
      objects: [
        for (final object in document.objects)
          if (object.id == id) next else object,
      ],
    );
  }
}
