import 'dart:convert';
import 'dart:io';

import 'package:skapie/scene/scene_document.dart';
import 'package:skapie/scene/scene_json_codec.dart';

/// Writes `scene.json` under the process working directory (the repo root
/// when launched with `flutter run` from this project).
const String projectSceneRelativePath = '.skapie/scene.json';

class SceneFilePersistence {
  SceneFilePersistence(this.file);

  factory SceneFilePersistence.projectDefault() {
    return SceneFilePersistence(File(projectSceneRelativePath));
  }

  final File file;

  Future<SceneDocument?> read() async {
    if (!await file.exists()) {
      return null;
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(text);
    return SceneDocument.fromJson(asJsonMap(decoded, 'scene.json'));
  }

  Future<void> write(SceneDocument document) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(document.toJson())}\n');
  }
}
