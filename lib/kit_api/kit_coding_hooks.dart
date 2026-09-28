import 'package:skapie/tools/coding/edit_tool.dart';
import 'package:skapie/tools/coding/read_tool.dart';
import 'package:skapie/tools/coding/shell_tool.dart';
import 'package:skapie/tools/coding/write_tool.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

/// File and process hooks a kit program can ask the host to run.
/// The kit chooses the hook. The host keeps the folder grant.
Future<Map<String, Object?>> runReadHook({
  required String path,
  required Map<String, Object?> args,
  RepositoryPermission permission = const SystemRepositoryPermission(),
}) {
  return readTool(path: path, permission: permission).run(args);
}

Future<Map<String, Object?>> runWriteHook({
  required String path,
  required Map<String, Object?> args,
  PatchWritePermission permission = const SystemPatchWritePermission(),
}) {
  return writeTool(path: path, permission: permission).run(args);
}

Future<Map<String, Object?>> runEditHook({
  required String path,
  required Map<String, Object?> args,
  PatchWritePermission permission = const SystemPatchWritePermission(),
}) {
  return editTool(path: path, permission: permission).run(args);
}

Future<Map<String, Object?>> runShellHook({
  required String path,
  required Map<String, Object?> args,
  PatchWritePermission permission = const SystemPatchWritePermission(),
}) {
  return shellTool(path: path, permission: permission).run(args);
}
