import 'dart:convert';

import 'package:skapie/tools/coding/scoped_path.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/tool.dart';

const _editTextBound = 512 * 1024;

/// Edit: replace one exact substring in an existing file inside the write grant.
AgentTool editTool({
  required String path,
  PatchWritePermission permission = const SystemPatchWritePermission(),
}) {
  return AgentTool(
    name: 'edit',
    description:
        'Replace exact existing text in one repository file. The old text must '
        'appear exactly once. Requires a live write grant.',
    parameters: jsonSchemaObject(
      properties: {
        'path': {'type': 'string', 'description': 'Repository-relative path'},
        'oldText': {'type': 'string', 'description': 'Exact existing text'},
        'newText': {'type': 'string', 'description': 'Replacement text'},
      },
      required: const ['path', 'oldText', 'newText'],
    ),
    run: (args) async {
      try {
        final oldText = requiredString(args, 'oldText');
        final newText = args['newText']?.toString() ?? '';
        if (oldText.length > _editTextBound || newText.length > _editTextBound) {
          return toolError('The anchor or replacement exceeds the text bound.');
        }
        final root = await resolveScopedRoot(
          path: path,
          accessible: permission.canWrite,
          expiredMessage: 'Write access expired. Choose the write folder again.',
        );
        final file = await scopedExistingFile(root, requiredString(args, 'path'));
        if (await file.length() > 2 * 1024 * 1024) {
          return toolError('File exceeds the 2 MB limit.');
        }
        final bytes = await file.readAsBytes();
        if (bytes.contains(0)) {
          return toolError('Binary files are not editable.');
        }
        String content;
        try {
          content = utf8.decode(bytes);
        } on FormatException {
          return toolError('Only UTF-8 text files are editable.');
        }
        final first = content.indexOf(oldText);
        if (first < 0) {
          return toolError('The existing text is not in the file.');
        }
        if (content.indexOf(oldText, first + oldText.length) >= 0) {
          return toolError('The existing text matches more than once.');
        }
        final crlf = content.contains('\r\n');
        final styled = crlf
            ? newText.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')
            : newText.replaceAll('\r\n', '\n');
        final replacement = content.replaceRange(
          first,
          first + oldText.length,
          styled,
        );
        if (replacement == content) {
          return toolError('Replacement makes no change to the file.');
        }
        await file.writeAsBytes(utf8.encode(replacement), flush: true);
        return {
          'ok': true,
          'path': args['path'],
          'bytes': utf8.encode(replacement).length,
        };
      } catch (error) {
        return toolError('$error');
      }
    },
  );
}
