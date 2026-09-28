import 'dart:ui';

import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

/// A folder grant that does not ask the operating system.
class AllowRead implements RepositoryPermission {
  const AllowRead();

  @override
  Future<String?> chooseDirectory() async => null;

  @override
  Future<bool> canRead(String path) async => true;
}

/// Cable [toolFrameId] to a Repository whose read folder is already set.
void grantRead(KitApi kitApi, String toolFrameId) {
  final repo = kitApi.instantiate(
    codingRepositoryKitId,
    origin: const Offset(-400, 400),
  );
  kitApi.updateProps(repo.first, {repositoryPathProp: '/tmp/skapie-test'});
  connectRepositoryToTool(
    kitApi: kitApi,
    repositoryFrameId: repo.first,
    toolFrameId: toolFrameId,
  );
}
