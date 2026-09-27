import 'package:skapie/tools/coding/repository_reader.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/tool.dart';

/// Read: list, search, or read inside the granted repository. Read-only.
AgentTool readTool({
  required String path,
  RepositoryPermission permission = const SystemRepositoryPermission(),
}) {
  final reader = RepositoryReader(path: path, permission: permission);
  return AgentTool(
    name: 'read',
    description:
        'List, search, or read files inside the connected repository. Read-only.',
    parameters: jsonSchemaObject(
      properties: {
        'action': {
          'type': 'string',
          'enum': ['list', 'search', 'read'],
          'description': 'list files, search text, or read one file',
        },
        'path': {
          'type': 'string',
          'description': 'Repository-relative path for action=read',
        },
        'query': {
          'type': 'string',
          'description': 'Text to find for action=search',
        },
        'startLine': {'type': 'integer'},
        'lineCount': {'type': 'integer', 'description': 'At most 200 lines'},
        'limit': {'type': 'integer', 'description': 'Max files for list, up to 500'},
      },
      required: const ['action'],
    ),
    run: (args) async {
      try {
        final action = requiredString(args, 'action');
        final Future<Map<String, Object?>> result = switch (action) {
          'list' => reader.listFiles((args['limit'] as num?)?.toInt() ?? 200),
          'search' => reader.searchText(requiredString(args, 'query')),
          'read' => reader.readFile(
            requiredString(args, 'path'),
            startLine: (args['startLine'] as num?)?.toInt() ?? 1,
            lineCount: (args['lineCount'] as num?)?.toInt() ?? 160,
          ),
          _ => throw FormatException('Unknown read action: $action'),
        };
        return await result;
      } catch (error) {
        return toolError('$error');
      }
    },
  );
}
