import 'package:collection/collection.dart';
import 'package:skapie/scene/scene_json_codec.dart';

/// Last-saved camera. Live pan/zoom still lives on the canvas.
///
/// [offsetX]/[offsetY] are the world point shown at the viewport center,
/// not the world origin.
class SceneCameraSnapshot {
  const SceneCameraSnapshot({
    this.offsetX = 0,
    this.offsetY = 0,
    this.zoom = 1,
  });

  final double offsetX;
  final double offsetY;
  final double zoom;

  Map<String, Object?> toJson() => {
    'offsetX': offsetX,
    'offsetY': offsetY,
    'zoom': zoom,
  };

  factory SceneCameraSnapshot.fromJson(Map<String, Object?> json) {
    return SceneCameraSnapshot(
      offsetX: readDouble(json, 'offsetX', 0),
      offsetY: readDouble(json, 'offsetY', 0),
      zoom: readDouble(json, 'zoom', 1),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneCameraSnapshot &&
        other.offsetX == offsetX &&
        other.offsetY == offsetY &&
        other.zoom == zoom;
  }

  @override
  int get hashCode => Object.hash(offsetX, offsetY, zoom);
}

/// One typed item in the scene. Not a graph node (ports/cables are reserved).
class SceneObject {
  const SceneObject({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.zIndex = 0,
    this.props = const {},
    this.locked = false,
    this.visible = true,
  });

  final String id;
  final String type;

  /// World-space frame. `(x, y)` is the top-left of the unrotated box.
  final double x;
  final double y;
  final double width;
  final double height;

  /// Rotation in radians, around the frame center.
  final double rotation;
  final int zIndex;
  final Map<String, Object?> props;
  final bool locked;
  final bool visible;

  SceneObject copyWith({
    String? type,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
    Map<String, Object?>? props,
    bool? locked,
    bool? visible,
  }) {
    return SceneObject(
      id: id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      props: props ?? this.props,
      locked: locked ?? this.locked,
      visible: visible ?? this.visible,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'zIndex': zIndex,
    'props': props,
    'locked': locked,
    'visible': visible,
  };

  factory SceneObject.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final type = json['type'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('SceneObject.id is required');
    }
    if (type is! String || type.isEmpty) {
      throw const FormatException('SceneObject.type is required');
    }
    return SceneObject(
      id: id,
      type: type,
      x: readDouble(json, 'x'),
      y: readDouble(json, 'y'),
      width: readDouble(json, 'width'),
      height: readDouble(json, 'height'),
      rotation: readDouble(json, 'rotation', 0),
      zIndex: readInt(json, 'zIndex', 0),
      props: readProps(json['props']),
      locked: readBool(json, 'locked', false),
      visible: readBool(json, 'visible', true),
    );
  }

  static const _deep = DeepCollectionEquality();

  @override
  bool operator ==(Object other) {
    return other is SceneObject &&
        other.id == id &&
        other.type == type &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height &&
        other.rotation == rotation &&
        other.zIndex == zIndex &&
        other.locked == locked &&
        other.visible == visible &&
        _deep.equals(other.props, props);
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    x,
    y,
    width,
    height,
    rotation,
    zIndex,
    locked,
    visible,
    _deep.hash(props),
  );
}
