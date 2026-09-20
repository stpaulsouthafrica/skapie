import 'dart:convert';
import 'dart:io';

import 'package:skapie/scene/scene_document.dart';
import 'package:skapie/scene/scene_json_codec.dart';

class SceneFilePersistence {
  SceneFilePersistence(this.file);

  final File file;

  String get absolutePath => file.absolute.path;

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
