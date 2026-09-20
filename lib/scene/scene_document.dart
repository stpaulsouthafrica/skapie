import 'package:collection/collection.dart';
import 'package:skapie/scene/scene_constants.dart';
import 'package:skapie/scene/scene_ids.dart';
import 'package:skapie/scene/scene_json_codec.dart';
import 'package:skapie/scene/scene_object.dart';

class SceneDocument {
  const SceneDocument({
    required this.id,
    required this.schemaVersion,
    this.objects = const [],
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
  final List<SceneObject> objects;

  /// Last saved camera. Not the live canvas camera.
  final SceneCameraSnapshot? camera;

  SceneDocument copyWith({
    List<SceneObject>? objects,
    SceneCameraSnapshot? camera,
    bool clearCamera = false,
  }) {
    return SceneDocument(
      id: id,
      schemaVersion: schemaVersion,
      objects: objects ?? this.objects,
      camera: clearCamera ? null : (camera ?? this.camera),
    );
  }

  SceneObject? objectById(String id) {
    for (final object in objects) {
      if (object.id == id) {
        return object;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'schemaVersion': schemaVersion,
    'objects': [for (final object in objects) object.toJson()],
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
    SceneCameraSnapshot? camera;
    final rawCamera = json['camera'];
    if (rawCamera != null) {
      camera = SceneCameraSnapshot.fromJson(asJsonMap(rawCamera, 'camera'));
    }
    return SceneDocument(
      id: id,
      schemaVersion: version.toInt(),
      objects: _readObjects(json),
      camera: camera,
    );
  }

  /// Prefer `objects`. Legacy Phase 3 files used `nodes`; both stay schema 1.
  static List<SceneObject> _readObjects(Map<String, Object?> json) {
    final raw = json.containsKey('objects') ? json['objects'] : json['nodes'];
    if (raw == null) {
      return const [];
    }
    if (raw is! List) {
      throw const FormatException('SceneDocument.objects must be a list');
    }
    return [
      for (final item in raw) SceneObject.fromJson(asJsonMap(item, 'object')),
    ];
  }

  static const _listEq = ListEquality<SceneObject>();

  @override
  bool operator ==(Object other) {
    return other is SceneDocument &&
        other.id == id &&
        other.schemaVersion == schemaVersion &&
        other.camera == camera &&
        _listEq.equals(other.objects, objects);
  }

  @override
  int get hashCode =>
      Object.hash(id, schemaVersion, camera, _listEq.hash(objects));
}
