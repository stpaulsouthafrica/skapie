import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/scene/scene_path.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('skapie_path_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('override dart-define path wins when absolute', () {
    final appSupport = Directory('${temp.path}/support');
    final override = File('${temp.path}/custom/scene.json');
    final resolved = resolveScenePath(
      dartDefinePath: override.path,
      appSupportDirectory: appSupport,
    );
    expect(resolved.file.absolute.path, override.absolute.path);
    expect(resolved.source, ScenePathSource.override);
    expect(resolved.warning, isNull);
  });

  test('env path is used when dart-define is empty', () {
    final appSupport = Directory('${temp.path}/support');
    final envFile = File('${temp.path}/env/scene.json');
    final resolved = resolveScenePath(
      envPath: envFile.path,
      appSupportDirectory: appSupport,
    );
    expect(resolved.file.absolute.path, envFile.absolute.path);
    expect(resolved.source, ScenePathSource.override);
  });

  test('relative override is rejected and falls back to app support', () {
    final appSupport = Directory('${temp.path}/support');
    final resolved = resolveScenePath(
      dartDefinePath: 'relative/scene.json',
      appSupportDirectory: appSupport,
    );
    expect(resolved.source, ScenePathSource.appSupport);
    expect(resolved.file.path, endsWith('/skapie/scene.json'));
    expect(resolved.warning, isNotNull);
  });

  test('project mode uses absolute project root, never cwd', () {
    final appSupport = Directory('${temp.path}/support');
    final project = Directory('${temp.path}/repo');
    final resolved = resolveScenePath(
      useProjectScene: true,
      projectRoot: project.path,
      appSupportDirectory: appSupport,
    );
    expect(resolved.source, ScenePathSource.project);
    expect(
      resolved.file.absolute.path,
      File('${project.path}/.skapie/scene.json').absolute.path,
    );
  });

  test(
    'project mode without absolute root falls back to app support with warning',
    () {
      final appSupport = Directory('${temp.path}/support');
      final resolved = resolveScenePath(
        useProjectScene: true,
        projectRoot: 'not-absolute',
        appSupportDirectory: appSupport,
      );
      expect(resolved.source, ScenePathSource.appSupport);
      expect(resolved.warning, contains('project root'));
    },
  );

  test('default is app support skapie/scene.json', () {
    final appSupport = Directory('${temp.path}/support');
    final resolved = resolveScenePath(appSupportDirectory: appSupport);
    expect(resolved.source, ScenePathSource.appSupport);
    expect(
      resolved.file.absolute.path,
      File('${appSupport.path}/skapie/scene.json').absolute.path,
    );
  });

  test('scenePathLabel shortens Application Support paths', () {
    expect(
      scenePathLabel(
        '/Users/me/Library/Containers/com.skapie.skapie/Data/Library/Application Support/com.skapie.skapie/skapie/scene.json',
      ),
      'App Support',
    );
  });

  test('scenePathLabel shortens project-scene paths', () {
    expect(
      scenePathLabel('/Users/me/Development/skapie/.skapie/scene.json'),
      '.skapie/scene.json',
    );
  });

  test('scenePathLabel uses the last two segments otherwise', () {
    expect(scenePathLabel('/tmp/custom/my-scene.json'), 'custom/my-scene.json');
  });
}
