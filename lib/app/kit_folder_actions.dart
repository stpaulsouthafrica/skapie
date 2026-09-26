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
  final name = path.split('/').where((part) => part.isNotEmpty).last;
  for (final member
      in kitMembers(document: kitApi.store.document, selectedId: frameId) ??
          const <SceneObject>[]) {
    if (member.props[skapieRoleProp] == 'body') {
      kitApi.updateProps(member.id, {'content': '$name\nRead-only repository'});
    }
  }
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
