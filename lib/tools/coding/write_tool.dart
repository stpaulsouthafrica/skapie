import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:skapie/tools/coding/scoped_path.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/tool.dart';

const _writeTextBound = 512 * 1024;

/// Write: create or replace one UTF-8 file inside the write grant.
AgentTool writeTool({
  required String path,
  PatchWritePermission permission = const SystemPatchWritePermission(),
}) {
  return AgentTool(
    name: 'write',
    description:
        'Create or replace one UTF-8 file inside the granted repository. '
        'Requires a live write grant. Provide expectedFingerprint to refuse a stale overwrite.',
    parameters: jsonSchemaObject(
      properties: {
        'path': {'type': 'string', 'description': 'Repository-relative path'},
        'content': {'type': 'string', 'description': 'Full file text'},
        'expectedFingerprint': {
          'type': 'string',
          'description': 'Optional sha256 of the current file before replacing',
        },
      },
      required: const ['path', 'content'],
    ),
    run: (args) async {
      try {
        final content = args['content'];
        if (content is! String) {
          return toolError('Expected string "content"');
        }
        if (utf8.encode(content).length > _writeTextBound) {
          return toolError('Content exceeds the 512 KB write limit.');
        }
        final root = await resolveScopedRoot(
          path: path,
          accessible: permission.canWrite,
          expiredMessage: 'Write access expired. Choose the write folder again.',
        );
        final file = await scopedWritableFile(root, requiredString(args, 'path'));
        final existed = await file.exists();
        final expected = args['expectedFingerprint']?.toString() ?? '';
        if (existed && expected.isNotEmpty) {
          final current = await file.readAsBytes();
          if (sha256.convert(current).toString() != expected) {
            return toolError(
              'Conflict: the file changed since expectedFingerprint.',
            );
          }
        }
        await file.writeAsBytes(utf8.encode(content), flush: true);
        return {
          'ok': true,
          'path': args['path'],
          'bytes': utf8.encode(content).length,
          'created': !existed,
        };
      } catch (error) {
        return toolError('$error');
      }
    },
  );
}
