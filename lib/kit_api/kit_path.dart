import 'dart:io';

const String kitsSubdir = 'kits';
const String appSupportKitsSubdir = 'skapie/kits';

class ResolvedKitsRoot {
  const ResolvedKitsRoot({
    required this.directory,
    required this.source,
    this.warning,
  });

  final Directory directory;
  final String source;
  final String? warning;
}

bool _isAbsolutePath(String path) => path.isNotEmpty && File(path).isAbsolute;

Directory _appSupportKits(Directory appSupportDirectory) {
  return Directory('${appSupportDirectory.path}/$appSupportKitsSubdir');
}

/// Resolve the kits shelf. Never uses cwd as the default.
ResolvedKitsRoot resolveKitsRoot({
  String? dartDefinePath,
  String? envPath,
  String? projectRoot,
  required Directory appSupportDirectory,
}) {
  final define = dartDefinePath?.trim() ?? '';
  if (define.isNotEmpty) {
    if (_isAbsolutePath(define)) {
      return ResolvedKitsRoot(directory: Directory(define), source: 'override');
    }
    return ResolvedKitsRoot(
      directory: _appSupportKits(appSupportDirectory),
      source: 'appSupport',
      warning:
          'SKAPIE_KITS_ROOT must be absolute (got "$define"); using Application Support.',
    );
  }

  final env = envPath?.trim() ?? '';
  if (env.isNotEmpty) {
    if (_isAbsolutePath(env)) {
      return ResolvedKitsRoot(directory: Directory(env), source: 'override');
    }
    return ResolvedKitsRoot(
      directory: _appSupportKits(appSupportDirectory),
      source: 'appSupport',
      warning:
          'SKAPIE_KITS_ROOT must be absolute (got "$env"); using Application Support.',
    );
  }

  final root = projectRoot?.trim() ?? '';
  if (_isAbsolutePath(root)) {
    return ResolvedKitsRoot(
      directory: Directory('$root/$kitsSubdir'),
      source: 'project',
    );
  }

  return ResolvedKitsRoot(
    directory: _appSupportKits(appSupportDirectory),
    source: 'appSupport',
    warning: 'No absolute SKAPIE_KITS_ROOT or SKAPIE_PROJECT_ROOT; using Application Support kits.',
  );
}
