import 'dart:io';

import 'package:skapie/tools/coding/repository_reader.dart';
import 'package:skapie/tools/coding/scoped_path.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/tool.dart';

/// Demoted repository read tools, kept as rebuild references (see
/// docs/phase_12_rebuild_notes.md). The default board uses the single `read`
/// tool instead.
const repositoryToolNames = <String>{
  'repo_list_files',
  'repo_search_text',
  'repo_read_file',
  'repo_git_status',
  'repo_git_diff',
};

/// macOS /usr/bin/git is a launcher that invokes xcrun, which is unavailable
/// inside the app sandbox. Use the installed Git binary directly, as the
/// native Check runner does.
String? repositoryGitExecutable() {
  if (!Platform.isMacOS) return 'git';
  for (final path in [
    '/Library/Developer/CommandLineTools/usr/bin/git',
    '/Applications/Xcode.app/Contents/Developer/usr/bin/git',
  ]) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

AgentTool? repositoryToolForName(
  String name, {
  required String repositoryPath,
  RepositoryPermission permission = const SystemRepositoryPermission(),
}) {
  final reader = RepositoryReader(
    path: repositoryPath,
    permission: permission,
  );
  final git = _GitReader(path: repositoryPath, permission: permission);
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
      run: (_) => git.status(),
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
      run: (args) => git.diff(
        path: args['path']?.toString(),
        staged: args['staged'] == true,
      ),
    ),
    _ => null,
  };
}

/// Demoted Git reads. Kept only so `repo_git_status` and `repo_git_diff` stay
/// loadable from examples/.
class _GitReader {
  const _GitReader({required this.path, required this.permission});

  final String path;
  final RepositoryPermission permission;

  Future<Directory> _root() {
    return resolveScopedRoot(
      path: path,
      accessible: permission.canRead,
      expiredMessage: 'Repository access expired. Choose its folder again.',
    );
  }

  Future<Map<String, Object?>> status() async {
    final root = await _root();
    return _git(root, [
      'status',
      '--short',
      '--branch',
      '--untracked-files=normal',
    ]);
  }

  Future<Map<String, Object?>> diff({String? path, bool staged = false}) async {
    final root = await _root();
    final args = <String>['diff', '--no-ext-diff'];
    if (staged) {
      args.add('--cached');
    }
    final requested = path?.trim() ?? '';
    if (requested.isNotEmpty) {
      safeRelativeParts(requested);
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
        safeRelativeParts(name);
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
    final git = repositoryGitExecutable();
    if (git == null) {
      return toolError(
        'Installed Git was not found. Install Xcode Command Line Tools.',
      );
    }
    final result = await Process.run(
      git,
      args,
      workingDirectory: root.path,
      environment: Platform.isMacOS
          ? {
              'PATH': '/usr/bin:/bin',
              'LANG': 'C',
              'LC_ALL': 'C',
              'HOME': '/var/empty',
              'GIT_CONFIG_NOSYSTEM': '1',
              'GIT_CONFIG_GLOBAL': '/dev/null',
              'GIT_OPTIONAL_LOCKS': '0',
              'GIT_TERMINAL_PROMPT': '0',
              'GIT_PAGER': 'cat',
            }
          : {'GIT_OPTIONAL_LOCKS': '0', 'GIT_PAGER': 'cat'},
      includeParentEnvironment: !Platform.isMacOS,
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
