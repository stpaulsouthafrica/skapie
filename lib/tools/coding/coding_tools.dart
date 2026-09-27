import 'package:skapie/tools/coding/edit_tool.dart';
import 'package:skapie/tools/coding/read_tool.dart';
import 'package:skapie/tools/coding/shell_tool.dart';
import 'package:skapie/tools/coding/write_tool.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/tool.dart';

/// The four starter coding tools.
const codingToolNames = <String>{'read', 'write', 'edit', 'shell'};

/// Which grant a tool needs: the read folder or the write folder.
enum CodingGrant { read, write }

CodingGrant? codingGrantForName(String name) {
  return switch (name) {
    'read' => CodingGrant.read,
    'write' || 'edit' || 'shell' => CodingGrant.write,
    _ => null,
  };
}

AgentTool? codingToolForName(
  String name, {
  required String readPath,
  required String writePath,
  RepositoryPermission readPermission = const SystemRepositoryPermission(),
  PatchWritePermission writePermission = const SystemPatchWritePermission(),
}) {
  return switch (name) {
    'read' => readTool(path: readPath, permission: readPermission),
    'write' => writeTool(path: writePath, permission: writePermission),
    'edit' => editTool(path: writePath, permission: writePermission),
    'shell' => shellTool(path: writePath, permission: writePermission),
    _ => null,
  };
}
