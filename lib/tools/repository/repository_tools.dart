import 'dart:convert';
import 'dart:io';

import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/tool.dart';

const repositoryToolNames = <String>{
  'repo_list_files',
  'repo_search_text',
  'repo_read_file',
  'repo_git_status',
  'repo_git_diff',
};

const _skippedDirectories = <String>{
  '.git',
  '.dart_tool',
  '.idea',
  '.next',
  'build',
  'node_modules',
  'Pods',
  'DerivedData',
};

bool _sensitiveName(String name) {
  final lower = name.toLowerCase();
  return lower == '.env' ||
      lower.startsWith('.env.') ||
      lower.endsWith('.pem') ||
      lower.endsWith('.key') ||
      lower == 'id_rsa' ||
      lower == 'id_ed25519';
}

List<String> _safeParts(String relative) {
  final parts = relative.replaceAll('\\', '/').split('/');
  if (relative.trim().isEmpty ||
      relative.startsWith('/') ||
      relative.contains('\u0000') ||
      parts.any((part) => part == '..' || part == '.' || part.isEmpty) ||
      parts.any(
        (part) => _sensitiveName(part) || _skippedDirectories.contains(part),
      ) ||
      (Platform.isWindows && relative.contains(':'))) {
    throw const FormatException('Expected a safe relative file path.');
  }
  return parts;
}

/// Host-owned, bounded reads. A tool kit grants one operation and a Repository
/// cable supplies its root. The model never chooses an absolute root.
class RepositoryReader {
  const RepositoryReader({required this.path, required this.permission});

  final String path;
  final RepositoryPermission permission;

  Future<Directory> _root() async {
    if (path.trim().isEmpty) {
      throw StateError('Connect a Repository kit and choose its folder.');
    }
    if (!await permission.canRead(path)) {
      throw StateError('Repository access expired. Choose its folder again.');
    }
    final root = Directory(path);
    if (!await root.exists()) {
      throw StateError('Repository folder is missing: $path');
    }
    return Directory(await root.resolveSymbolicLinks());
  }

  Future<File> _file(Directory root, String relative) async {
    final parts = _safeParts(relative);
    final file = File(
      '${root.path}${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}',
    );
    if (!await file.exists()) {
      throw FileSystemException('File not found', relative);
    }
    final canonical = await file.resolveSymbolicLinks();
    if (!canonical.startsWith('${root.path}${Platform.pathSeparator}')) {
      throw const FormatException('File resolves outside the repository.');
    }
    return File(canonical);
  }

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
          if (!_skippedDirectories.contains(name)) {
            queue.add(entity);
          }
        } else if (entity is File && !_sensitiveName(name)) {
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
          found.add({
            'path': entry.path,
            'line': i + 1,
            'text': lines[i].trim().substring(
              0,
              lines[i].trim().length.clamp(0, 240),
            ),
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

  Future<Map<String, Object?>> gitStatus() async {
    final root = await _root();
    return _git(root, [
      'status',
      '--short',
      '--branch',
      '--untracked-files=normal',
    ]);
  }

  Future<Map<String, Object?>> gitDiff({
    String? path,
    bool staged = false,
  }) async {
    final root = await _root();
    final args = <String>['diff', '--no-ext-diff'];
    if (staged) {
      args.add('--cached');
    }
    final requested = path?.trim() ?? '';
    if (requested.isNotEmpty) {
      _safeParts(requested);
    }
    final namesResult = await _git(root, [...args, '--name-only', '-z']);
    if (namesResult['ok'] != true) {
      return namesResult;
    }
    final names = (namesResult['output'] as String)
        .split('\u0000')
        .where((name) => name.isNotEmpty)
        .toList();
    final selected = <String>[];
    for (final name in names) {
      try {
        _safeParts(name);
      } on FormatException {
        continue;
      }
      if (requested.isEmpty || name == requested) {
        selected.add(name);
      }
    }
    final buffer = StringBuffer();
    var truncated = namesResult['truncated'] == true || selected.length > 30;
    for (final name in selected.take(30)) {
      final result = await _git(root, [...args, '--', name]);
      if (result['ok'] != true) {
        return result;
      }
      buffer.write(result['output']);
      truncated = truncated || result['truncated'] == true;
      if (buffer.length > 24000) {
        truncated = true;
        break;
      }
    }
    final output = buffer.toString();
    return {
      'ok': true,
      'output': output.length > 24000 ? output.substring(0, 24000) : output,
      'truncated': truncated,
    };
  }

  Future<Map<String, Object?>> _git(Directory root, List<String> args) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: root.path,
      environment: {'GIT_OPTIONAL_LOCKS': '0', 'GIT_PAGER': 'cat'},
    ).timeout(const Duration(seconds: 15));
    final output = result.stdout.toString();
    final error = result.stderr.toString();
    if (result.exitCode != 0) {
      return toolError(
        error.trim().isEmpty ? 'Git exited ${result.exitCode}' : error.trim(),
      );
    }
    return {
      'ok': true,
      'output': output.length > 24000 ? output.substring(0, 24000) : output,
      'truncated': output.length > 24000,
    };
  }
}

AgentTool? repositoryToolForName(
  String name, {
  required String repositoryPath,
  RepositoryPermission permission = const SystemRepositoryPermission(),
}) {
  final reader = RepositoryReader(path: repositoryPath, permission: permission);
  return switch (name) {
    'repo_list_files' => AgentTool(
      name: name,
      description: 'List files in the connected repository. Excludes generated and secret files.',
      parameters: jsonSchemaObject(
        properties: {
          'limit': {
            'type': 'integer',
            'description': 'Maximum files, up to 500',
          },
        },
      ),
      run: (args) => reader.listFiles((args['limit'] as num?)?.toInt() ?? 200),
    ),
    'repo_search_text' => AgentTool(
      name: name,
      description: 'Search text in the connected repository. Returns file paths and line numbers.',
      parameters: jsonSchemaObject(
        properties: {
          'query': {'type': 'string'},
        },
        required: const ['query'],
      ),
      run: (args) => reader.searchText(requiredString(args, 'query')),
    ),
    'repo_read_file' => AgentTool(
      name: name,
      description: 'Read a bounded line range from one repository file.',
      parameters: jsonSchemaObject(
        properties: {
          'path': {'type': 'string', 'description': 'Repository-relative path'},
          'startLine': {'type': 'integer'},
          'lineCount': {'type': 'integer', 'description': 'At most 200 lines'},
        },
        required: const ['path'],
      ),
      run: (args) => reader.readFile(
        requiredString(args, 'path'),
        startLine: (args['startLine'] as num?)?.toInt() ?? 1,
        lineCount: (args['lineCount'] as num?)?.toInt() ?? 160,
      ),
    ),
    'repo_git_status' => AgentTool(
      name: name,
      description: 'Read Git branch and working tree status in the connected repository.',
      parameters: jsonSchemaObject(),
      run: (_) => reader.gitStatus(),
    ),
    'repo_git_diff' => AgentTool(
      name: name,
      description: 'Read a bounded working tree or staged Git diff.',
      parameters: jsonSchemaObject(
        properties: {
          'path': {
            'type': 'string',
            'description': 'Optional repository-relative file',
          },
          'staged': {'type': 'boolean'},
        },
      ),
      run: (args) => reader.gitDiff(
        path: args['path']?.toString(),
        staged: args['staged'] == true,
      ),
    ),
    _ => null,
  };
}
