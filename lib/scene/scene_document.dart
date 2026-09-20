import 'package:collection/collection.dart';
import 'package:skapie/scene/scene_constants.dart';
import 'package:skapie/scene/scene_ids.dart';
import 'package:skapie/scene/scene_json_codec.dart';
import 'package:skapie/scene/scene_node.dart';

class SceneDocument {
  const SceneDocument({
    required this.id,
    required this.schemaVersion,
    this.nodes = const [],
    this.camera,
  });

  factory SceneDocument.empty() {
    return SceneDocument(
      id: newSceneId('doc'),
      schemaVersion: currentSceneSchemaVersion,
    );
  }

  final String id;
  final int schemaVersion;
  final List<SceneNode> nodes;

  /// Last saved camera. Not the live viewport camera.
  final SceneCameraSnapshot? camera;

  SceneDocument copyWith({
    List<SceneNode>? nodes,
    SceneCameraSnapshot? camera,
    bool clearCamera = false,
  }) {
    return SceneDocument(
      id: id,
      schemaVersion: schemaVersion,
      nodes: nodes ?? this.nodes,
      camera: clearCamera ? null : (camera ?? this.camera),
    );
  }

  SceneNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'schemaVersion': schemaVersion,
    'nodes': [for (final node in nodes) node.toJson()],
    if (camera != null) 'camera': camera!.toJson(),
  };

  factory SceneDocument.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final version = json['schemaVersion'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('SceneDocument.id is required');
    }
    if (version is! num) {
      throw const FormatException('SceneDocument.schemaVersion is required');
    }
    final rawNodes = json['nodes'];
    final nodes = <SceneNode>[];
    if (rawNodes != null) {
      if (rawNodes is! List) {
        throw const FormatException('SceneDocument.nodes must be a list');
      }
      for (final item in rawNodes) {
        nodes.add(SceneNode.fromJson(asJsonMap(item, 'node')));
      }
    }
    SceneCameraSnapshot? camera;
    final rawCamera = json['camera'];
    if (rawCamera != null) {
      camera = SceneCameraSnapshot.fromJson(asJsonMap(rawCamera, 'camera'));
    }
    return SceneDocument(
      id: id,
      schemaVersion: version.toInt(),
      nodes: nodes,
      camera: camera,
    );
  }

  static const _listEq = ListEquality<SceneNode>();

  @override
  bool operator ==(Object other) {
    return other is SceneDocument &&
        other.id == id &&
        other.schemaVersion == schemaVersion &&
        other.camera == camera &&
        _listEq.equals(other.nodes, nodes);
  }

  @override
  int get hashCode =>
      Object.hash(id, schemaVersion, camera, _listEq.hash(nodes));
}
