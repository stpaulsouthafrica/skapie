import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

/// The Inspector and canvas gestures share the same folder actions.
Future<bool> chooseRepositoryFolder({
  required KitApi kitApi,
  required String frameId,
  required RepositoryPermission permission,
  bool Function()? isActive,
}) async {
  final path = await permission.chooseDirectory();
  if (path == null || path.isEmpty) return false;
  if (isActive != null && !isActive()) return false;
  final frame = kitApi.store.document.objectById(frameId);
  if (frame == null || kitIdOf(frame) != codingRepositoryKitId) return false;

  kitApi.updateProps(frameId, {repositoryPathProp: path});
  _refreshRepositoryBody(kitApi, frameId);
  return true;
}

/// The Repository kit's second folder: the write grant for Write/Edit/Shell.
Future<bool> chooseRepositoryWriteFolder({
  required KitApi kitApi,
  required String frameId,
  required PatchWritePermission permission,
  bool Function()? isActive,
}) async {
  final path = await permission.chooseDirectory();
  if (path == null || path.isEmpty) return false;
  if (isActive != null && !isActive()) return false;
  final frame = kitApi.store.document.objectById(frameId);
  if (frame == null || kitIdOf(frame) != codingRepositoryKitId) return false;

  kitApi.updateProps(frameId, {repositoryWritePathProp: path});
  _refreshRepositoryBody(kitApi, frameId);
  return true;
}

Future<bool> chooseWriteScopeFolder({
  required KitApi kitApi,
  required String frameId,
  required PatchWritePermission permission,
  bool Function()? isActive,
}) async {
  final path = await permission.chooseDirectory();
  if (path == null || path.isEmpty) return false;
  if (isActive != null && !isActive()) return false;
  final frame = kitApi.store.document.objectById(frameId);
  if (frame == null || kitIdOf(frame) != codingWriteScopeKitId) return false;

  kitApi.updateProps(frameId, {writeScopePathProp: path});
  return true;
}

void _refreshRepositoryBody(KitApi kitApi, String frameId) {
  final frame = kitApi.store.document.objectById(frameId);
  if (frame == null) return;
  final read = _folderName(
    frame.props[repositoryPathProp]?.toString() ?? '',
  );
  final write = _folderName(
    frame.props[repositoryWritePathProp]?.toString() ?? '',
  );
  final content =
      'Read: ${read.isEmpty ? 'none' : read}\n'
      'Write: ${write.isEmpty ? 'none' : write}';
  for (final member
      in kitMembers(document: kitApi.store.document, selectedId: frameId) ??
          const <SceneObject>[]) {
    if (member.props[skapieRoleProp] == 'body') {
      kitApi.updateProps(member.id, {'content': content});
    }
  }
}

String _folderName(String path) {
  return path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';
}
