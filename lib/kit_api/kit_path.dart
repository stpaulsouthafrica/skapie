import 'dart:io';

const String kitsSubdir = 'kits';
const String appSupportKitsSubdir = 'skapie/kits';
const String userSkapieSubdir = '.skapie';
const String userKitsSubdir = '$userSkapieSubdir/$kitsSubdir';

class ResolvedKitsRoot {
  const ResolvedKitsRoot({
    required this.directory,
    required this.source,
    this.warning,
  });

  final Directory directory;

  /// `override`, `project`, `user`, or `appSupport`.
  final String source;
  final String? warning;
}

bool _isAbsolutePath(String path) => path.isNotEmpty && File(path).isAbsolute;

Directory _appSupportKits(Directory appSupportDirectory) {
  return Directory('${appSupportDirectory.path}/$appSupportKitsSubdir');
}

Directory _userKits(Directory homeDirectory) {
  return Directory('${homeDirectory.path}/$userKitsSubdir');
}

Directory? _homeDirectory() {
  final env = Platform.environment;
  final home = (env['HOME'] ?? env['USERPROFILE'] ?? '').trim();
  return home.isEmpty ? null : Directory(home);
}

/// The override path when it is absolute, else null. A non-empty relative
/// value is rejected with [warning].
({Directory? directory, String? warning}) _override(
  String? raw, {
  required String label,
}) {
  final path = raw?.trim() ?? '';
  if (path.isEmpty) {
    return (directory: null, warning: null);
  }
  if (_isAbsolutePath(path)) {
    return (directory: Directory(path), warning: null);
  }
  return (
    directory: null,
    warning: '$label must be absolute (got "$path")',
  );
}

/// Resolve the kits shelf. Never uses cwd as the default.
///
/// Order: `SKAPIE_KITS_ROOT` override, then `<SKAPIE_PROJECT_ROOT>/kits` for
/// development, then the user shelf `~/.skapie/kits`.
ResolvedKitsRoot resolveKitsRoot({
  String? dartDefinePath,
  String? envPath,
  String? projectRoot,
  Directory? homeDirectory,
  required Directory appSupportDirectory,
}) {
  final define = _override(dartDefinePath, label: 'SKAPIE_KITS_ROOT');
  if (define.directory != null) {
    return ResolvedKitsRoot(directory: define.directory!, source: 'override');
  }
  final env = _override(envPath, label: 'SKAPIE_KITS_ROOT');
  if (env.directory != null) {
    return ResolvedKitsRoot(directory: env.directory!, source: 'override');
  }
  var warning = _mergeWarning(define.warning, env.warning);

  final root = projectRoot?.trim() ?? '';
  if (_isAbsolutePath(root)) {
    return ResolvedKitsRoot(
      directory: Directory('$root/$kitsSubdir'),
      source: 'project',
      warning: warning,
    );
  }

  final home = homeDirectory ?? _homeDirectory();
  if (home != null) {
    return ResolvedKitsRoot(
      directory: _userKits(home),
      source: 'user',
      warning: warning,
    );
  }

  return ResolvedKitsRoot(
    directory: _appSupportKits(appSupportDirectory),
    source: 'appSupport',
    warning: warning ?? 'No home directory; using Application Support kits.',
  );
}

String? _mergeWarning(String? first, String? second) {
  if (first == null) {
    return second;
  }
  if (second == null) {
    return first;
  }
  return '$first; $second';
}

