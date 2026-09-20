import 'package:skapie/scene/scene_document.dart';
import 'package:skapie/scene/scene_node.dart';

/// The only scene mutations. Applied by [SceneStore.apply].
sealed class SceneOp {
  const SceneOp();

  SceneDocument apply(SceneDocument document);
}

final class AddNode extends SceneOp {
  const AddNode(this.node);

  final SceneNode node;

  @override
  SceneDocument apply(SceneDocument document) {
    if (document.nodeById(node.id) != null) {
      return document;
    }
    return document.copyWith(nodes: [...document.nodes, node]);
  }
}

final class RemoveNode extends SceneOp {
  const RemoveNode(this.id);

  final String id;

  @override
  SceneDocument apply(SceneDocument document) {
    if (document.nodeById(id) == null) {
      return document;
    }
    return document.copyWith(
      nodes: [
        for (final node in document.nodes)
          if (node.id != id) node,
      ],
    );
  }
}

final class UpdateNodeFrame extends SceneOp {
  const UpdateNodeFrame({
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
    final current = document.nodeById(id);
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
      nodes: [
        for (final node in document.nodes)
          if (node.id == id) next else node,
      ],
    );
  }
}

/// Shallow-merge [patch] into the node's props.
///
/// Keys with a `null` value are removed. Other existing keys are kept.
final class UpdateNodeProps extends SceneOp {
  const UpdateNodeProps(this.id, this.patch);

  final String id;
  final Map<String, Object?> patch;

  @override
  SceneDocument apply(SceneDocument document) {
    final current = document.nodeById(id);
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
      nodes: [
        for (final node in document.nodes)
          if (node.id == id) next else node,
      ],
    );
  }
}
