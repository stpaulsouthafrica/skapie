import 'dart:io';

const String sceneFileName = 'scene.json';
const String appSupportSceneSubdir = 'skapie';
const String projectSceneRelativePath = '.skapie/scene.json';
const String macosLegacyContainerId = 'com.skapie.skapie';

enum ScenePathSource { override, project, appSupport }

class ResolvedScenePath {
  const ResolvedScenePath({
    required this.file,
    required this.source,
    this.warning,
  });

  final File file;
  final ScenePathSource source;
  final String? warning;
}

bool _isAbsolutePath(String path) => path.isNotEmpty && File(path).isAbsolute;

File appSupportSceneFile(Directory appSupportDirectory) {
  return File(
    '${appSupportDirectory.path}/$appSupportSceneSubdir/$sceneFileName',
  );
}

/// Resolve the canonical scene file. Never uses cwd as the default location.
ResolvedScenePath resolveScenePath({
  String? dartDefinePath,
  String? envPath,
  bool useProjectScene = false,
  String? projectRoot,
  required Directory appSupportDirectory,
}) {
  final define = dartDefinePath?.trim() ?? '';
  if (define.isNotEmpty) {
    if (_isAbsolutePath(define)) {
      return ResolvedScenePath(
        file: File(define),
        source: ScenePathSource.override,
      );
    }
    return ResolvedScenePath(
      file: appSupportSceneFile(appSupportDirectory),
      source: ScenePathSource.appSupport,
      warning:
          'SKAPIE_SCENE_PATH must be absolute (got "$define"); using Application Support.',
    );
  }

  final env = envPath?.trim() ?? '';
  if (env.isNotEmpty) {
    if (_isAbsolutePath(env)) {
      return ResolvedScenePath(
        file: File(env),
        source: ScenePathSource.override,
      );
    }
    return ResolvedScenePath(
      file: appSupportSceneFile(appSupportDirectory),
      source: ScenePathSource.appSupport,
      warning:
          'SKAPIE_SCENE_PATH must be absolute (got "$env"); using Application Support.',
    );
  }

  if (useProjectScene) {
    final root = projectRoot?.trim() ?? '';
    if (_isAbsolutePath(root)) {
      return ResolvedScenePath(
        file: File('$root/$projectSceneRelativePath'),
        source: ScenePathSource.project,
      );
    }
    return ResolvedScenePath(
      file: appSupportSceneFile(appSupportDirectory),
      source: ScenePathSource.appSupport,
      warning: 'SKAPIE_USE_PROJECT_SCENE requested but project root is missing or not absolute; using Application Support.',
    );
  }

  return ResolvedScenePath(
    file: appSupportSceneFile(appSupportDirectory),
    source: ScenePathSource.appSupport,
  );
}

/// Short chrome label. Persistence and logs still use the absolute path.
String scenePathLabel(String absolutePath) {
  final normalized = absolutePath.replaceAll(r'\', '/');
  if (normalized.endsWith('/.skapie/scene.json')) {
    return '.skapie/scene.json';
  }
  if (normalized.contains('/Application Support/') &&
      normalized.endsWith('/skapie/scene.json')) {
    return 'App Support';
  }
  final parts = [
    for (final part in normalized.split('/'))
      if (part.isNotEmpty) part,
  ];
  if (parts.length >= 2) {
    return '${parts[parts.length - 2]}/${parts.last}';
  }
  return parts.isEmpty ? absolutePath : parts.last;
}

File? _macosContainerLegacyFile() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return null;
  }
  return File(
    '$home/Library/Containers/$macosLegacyContainerId/Data/.skapie/$sceneFileName',
  );
}

/// Copy a cwd-relative or macOS-container scene into [canonical] once.
Future<File?> migrateLegacySceneIfNeeded({
  required File canonical,
  Directory? cwd,
  File? extraLegacy,
}) async {
  final canonicalPath = canonical.absolute.path;
  if (await canonical.exists()) {
    return null;
  }

  final candidates = <File>[
    File('${(cwd ?? Directory.current).path}/$projectSceneRelativePath'),
    ?extraLegacy,
    ?_macosContainerLegacyFile(),
  ];

  final seen = <String>{};
  for (final candidate in candidates) {
    final path = candidate.absolute.path;
    if (!seen.add(path) || path == canonicalPath) {
      continue;
    }
    if (!await candidate.exists()) {
      continue;
    }
    await canonical.parent.create(recursive: true);
    await candidate.copy(canonicalPath);
    return canonical;
  }
  return null;
}
