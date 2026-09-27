import 'dart:io';

/// Generated or dependency folders that repository tools never read or write.
const skippedDirectories = <String>{
  '.git',
  '.dart_tool',
  '.idea',
  '.next',
  'build',
  'node_modules',
  'Pods',
  'DerivedData',
};

bool sensitiveName(String name) {
  final lower = name.toLowerCase();
  return lower == '.env' ||
      lower.startsWith('.env.') ||
      lower.endsWith('.pem') ||
      lower.endsWith('.key') ||
      lower == 'id_rsa' ||
      lower == 'id_ed25519';
}

/// Split a repository-relative path, refusing anything that could escape the
/// granted root or touch an excluded name.
List<String> safeRelativeParts(String relative) {
  final normalized = relative.replaceAll('\\', '/');
  final parts = normalized.split('/');
  if (relative.trim().isEmpty ||
      normalized.startsWith('/') ||
      relative.contains('\u0000') ||
      parts.any((part) => part == '..' || part == '.' || part.isEmpty) ||
      parts.any(
        (part) => sensitiveName(part) || skippedDirectories.contains(part),
      ) ||
      (Platform.isWindows && relative.contains(':'))) {
    throw const FormatException('Expected a safe relative file path.');
  }
  return parts;
}

/// Resolve a granted root, refusing when access is gone or the folder is gone.
Future<Directory> resolveScopedRoot({
  required String path,
  required Future<bool> Function(String path) accessible,
  required String expiredMessage,
  String missingMessage = 'Repository folder is missing.',
}) async {
  if (path.trim().isEmpty) {
    throw StateError('Connect a Repository kit and choose its folder.');
  }
  if (!await accessible(path)) {
    throw StateError(expiredMessage);
  }
  final root = Directory(path);
  if (!await root.exists()) {
    throw StateError('$missingMessage Path: $path');
  }
  return Directory(await root.resolveSymbolicLinks());
}

Future<File> scopedExistingFile(Directory root, String relative) async {
  final parts = safeRelativeParts(relative);
  final path =
      '${root.path}${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}';
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    throw FileSystemException('File not found', relative);
  }
  if (type != FileSystemEntityType.file) {
    throw const FormatException('Only an existing regular file is accepted.');
  }
  final canonical = await File(path).resolveSymbolicLinks();
  if (!canonical.startsWith('${root.path}${Platform.pathSeparator}')) {
    throw const FormatException('Path is outside the repository.');
  }
  return File(canonical);
}

/// Resolve a file that may not exist yet. Parent folders must already exist and
/// must not be symlinks.
Future<File> scopedWritableFile(Directory root, String relative) async {
  final parts = safeRelativeParts(relative);
  var current = root.path;
  for (final part in parts.take(parts.length - 1)) {
    current = '$current${Platform.pathSeparator}$part';
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw const FormatException(
        'Parent folder is missing or is not a folder.',
      );
    }
  }
  final path =
      '${root.path}${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}';
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw const FormatException('Symlink targets are not accepted.');
  }
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw const FormatException('Target is not a regular file.');
  }
  return File(path);
}
