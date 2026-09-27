import 'dart:convert';
import 'dart:io';

import 'package:skapie/tools/coding/scoped_path.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

/// Host-owned, bounded reads. The Repository cable supplies the root and the
/// live read grant; the model never chooses an absolute root.
class RepositoryReader {
  const RepositoryReader({required this.path, required this.permission});

  final String path;
  final RepositoryPermission permission;

  Future<Directory> _root() {
    return resolveScopedRoot(
      path: path,
      accessible: permission.canRead,
      expiredMessage: 'Repository access expired. Choose its folder again.',
      missingMessage: 'Repository folder is missing.',
    );
  }

  Future<File> _file(Directory root, String relative) =>
      scopedExistingFile(root, relative);

  Future<List<({String path, File file})>> _files(Directory root) async {
    final queue = <Directory>[root];
    final found = <({String path, File file})>[];
    var visited = 0;
    while (queue.isNotEmpty && visited < 10000 && found.length < 5000) {
      final dir = queue.removeLast();
      await for (final entity in dir.list(followLinks: false)) {
        visited++;
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        if (entity is Directory) {
          if (!skippedDirectories.contains(name)) {
            queue.add(entity);
          }
        } else if (entity is File && !sensitiveName(name)) {
          final relative = entity.path.substring(root.path.length + 1);
          found.add((path: relative, file: entity));
        }
        if (visited >= 10000 || found.length >= 5000) {
          break;
        }
      }
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  Future<Map<String, Object?>> listFiles(int limit) async {
    final root = await _root();
    final files = await _files(root);
    final count = limit.clamp(1, 500);
    return {
      'ok': true,
      'files': [for (final file in files.take(count)) file.path],
      'truncated': files.length > count || files.length >= 5000,
    };
  }

  Future<Map<String, Object?>> searchText(String query) async {
    if (query.trim().isEmpty) {
      throw const FormatException('Search query is empty.');
    }
    final root = await _root();
    final found = <Map<String, Object?>>[];
    for (final entry in await _files(root)) {
      if (found.length >= 80) {
        break;
      }
      if (await entry.file.length() > 1024 * 1024) {
        continue;
      }
      String content;
      try {
        content = await entry.file.readAsString();
      } on FormatException {
        continue;
      }
      if (content.contains('\u0000')) {
        continue;
      }
      final needle = query.toLowerCase();
      final lines = const LineSplitter().convert(content);
      for (var i = 0; i < lines.length && found.length < 80; i++) {
        if (lines[i].toLowerCase().contains(needle)) {
          final trimmed = lines[i].trim();
          found.add({
            'path': entry.path,
            'line': i + 1,
            'text': trimmed.substring(0, trimmed.length.clamp(0, 240)),
          });
        }
      }
    }
    return {'ok': true, 'matches': found, 'truncated': found.length >= 80};
  }

  Future<Map<String, Object?>> readFile(
    String relative, {
    int startLine = 1,
    int lineCount = 160,
  }) async {
    final root = await _root();
    final file = await _file(root, relative);
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('File exceeds the 2 MB read limit.');
    }
    final content = await file.readAsString();
    if (content.contains('\u0000')) {
      throw const FormatException(
        'Binary files are not readable by this tool.',
      );
    }
    final lines = const LineSplitter().convert(content);
    final from = startLine.clamp(1, lines.isEmpty ? 1 : lines.length);
    final count = lineCount.clamp(1, 200);
    final selected = lines.skip(from - 1).take(count).toList();
    final numbered = [
      for (var i = 0; i < selected.length; i++) '${from + i}: ${selected[i]}',
    ].join('\n');
    return {
      'ok': true,
      'path': relative,
      'startLine': from,
      'endLine': from + selected.length - 1,
      'content': numbered.length > 24000
          ? numbered.substring(0, 24000)
          : numbered,
      'truncated':
          from + selected.length - 1 < lines.length || numbered.length > 24000,
    };
  }
}
