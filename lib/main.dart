import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/scene/scene.dart';

const _scenePathDefine = String.fromEnvironment('SKAPIE_SCENE_PATH');
const _useProjectScene = bool.fromEnvironment('SKAPIE_USE_PROJECT_SCENE');
const _projectRootDefine = String.fromEnvironment('SKAPIE_PROJECT_ROOT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await bootstrapSceneStore();
  runApp(SkapieApp(store: store));
}

Future<SceneStore> bootstrapSceneStore({
  Directory? appSupportDirectory,
  Directory? cwd,
}) async {
  final appSupport =
      appSupportDirectory ?? await getApplicationSupportDirectory();
  final projectRoot = _projectRootDefine.trim().isNotEmpty
      ? _projectRootDefine
      : Platform.environment['SKAPIE_PROJECT_ROOT'];
  final resolved = resolveScenePath(
    dartDefinePath: _scenePathDefine,
    envPath: Platform.environment['SKAPIE_SCENE_PATH'],
    useProjectScene: _useProjectScene,
    projectRoot: projectRoot,
    appSupportDirectory: appSupport,
  );
  if (resolved.warning != null) {
    debugPrint('Skapie: ${resolved.warning}');
  }
  final migrated = await migrateLegacySceneIfNeeded(
    canonical: resolved.file,
    cwd: cwd,
  );
  if (migrated != null) {
    debugPrint('Skapie migrated scene into ${migrated.absolute.path}');
  }
  debugPrint('Skapie scene file: ${resolved.file.absolute.path}');
  final store = SceneStore(persistence: SceneFilePersistence(resolved.file));
  await store.load();
  return store;
}
