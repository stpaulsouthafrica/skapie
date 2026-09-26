import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/repository/repository_tools.dart';

class _GrantedRepository implements RepositoryPermission {
  @override
  Future<String?> chooseDirectory() async => null;

  @override
  Future<bool> canRead(String path) async => true;
}

void main() {
  test('macOS uses an installed Git binary, not the xcrun launcher', () {
    final executable = repositoryGitExecutable();
    if (Platform.isMacOS) {
      expect(executable, isNotNull);
      expect(executable, isNot('/usr/bin/git'));
      expect(File(executable!).existsSync(), isTrue);
    } else {
      expect(executable, 'git');
    }
  });

  test('repository Git status and diff read an edited working tree', () async {
    final root = await Directory.systemTemp.createTemp(
      'skapie-repository-git-',
    );
    addTearDown(() => root.delete(recursive: true));
    final executable = repositoryGitExecutable()!;

    Future<void> git(List<String> args) async {
      final result = await Process.run(
        executable,
        args,
        workingDirectory: root.path,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }

    await git(['init', '-q']);
    await git(['config', 'user.name', 'Skapie Test']);
    await git(['config', 'user.email', 'skapie@example.test']);
    final file = File('${root.path}/README.md');
    await file.writeAsString('before\n');
    await git(['add', 'README.md']);
    await git(['commit', '-qm', 'Initial file']);
    await file.writeAsString('after\n');

    final status = await repositoryToolForName(
      'repo_git_status',
      repositoryPath: root.path,
      permission: _GrantedRepository(),
    )!.run({});
    expect(status['ok'], isTrue);
    expect(status['output'], contains('README.md'));

    final diff = await repositoryToolForName(
      'repo_git_diff',
      repositoryPath: root.path,
      permission: _GrantedRepository(),
    )!.run({'path': 'README.md'});
    expect(diff['ok'], isTrue);
    expect(diff['output'], contains('-before'));
    expect(diff['output'], contains('+after'));
  });
}
