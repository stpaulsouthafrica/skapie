import 'dart:io';

import 'package:skapie/tools/coding/scoped_path.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/tool.dart';

const _shellSeconds = 60;
const _shellOutputLimit = 24000;

/// Why a command cannot run inside the granted root, or null when it can.
///
/// The app sandbox is the real boundary. This guard refuses obvious attempts to
/// point tools at paths outside the granted folder, so a test can see the
/// refusal and the model gets a clear reason.
String? shellEscapeReason(String command) {
  if (command.contains('\u0000')) {
    return 'The command contains a null byte.';
  }
  if (command.contains('..')) {
    return 'The command leaves the repository folder.';
  }
  for (final token in command.split(RegExp(r'\s+'))) {
    if (token.startsWith('/') || token.startsWith('~')) {
      return 'The command uses a path outside the repository folder.';
    }
  }
  return null;
}

/// Shell: run one command with the granted folder as its working folder.
AgentTool shellTool({
  required String path,
  PatchWritePermission permission = const SystemPatchWritePermission(),
}) {
  return AgentTool(
    name: 'shell',
    description:
        'Run one command with the granted repository as its working folder. '
        'Commands that point outside the repository are refused. Requires a live write grant.',
    parameters: jsonSchemaObject(
      properties: {
        'command': {'type': 'string', 'description': 'Command line to run'},
      },
      required: const ['command'],
    ),
    run: (args) async {
      final command = args['command']?.toString() ?? '';
      if (command.trim().isEmpty) {
        return toolError('Command is empty.');
      }
      final escape = shellEscapeReason(command);
      if (escape != null) {
        return toolError(escape);
      }
      if (!Platform.isMacOS && !Platform.isLinux) {
        return toolError('Shell is not available on this platform.');
      }
      try {
        final root = await resolveScopedRoot(
          path: path,
          accessible: permission.canWrite,
          expiredMessage: 'Write access expired. Choose the write folder again.',
        );
        final result = await Process.run(
          '/bin/sh',
          ['-c', command],
          workingDirectory: root.path,
          environment: const {
            'PATH': '/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin',
            'LANG': 'C',
            'LC_ALL': 'C',
          },
          includeParentEnvironment: false,
        ).timeout(const Duration(seconds: _shellSeconds));
        final stdout = result.stdout.toString();
        final stderr = result.stderr.toString();
        return {
          'ok': result.exitCode == 0,
          'exitCode': result.exitCode,
          'stdout': stdout.length > _shellOutputLimit
              ? stdout.substring(0, _shellOutputLimit)
              : stdout,
          'stderr': stderr.length > _shellOutputLimit
              ? stderr.substring(0, _shellOutputLimit)
              : stderr,
          'truncated':
              stdout.length > _shellOutputLimit ||
              stderr.length > _shellOutputLimit,
        };
      } catch (error) {
        return toolError('$error');
      }
    },
  );
}
