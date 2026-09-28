import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/coding_workflow_starter.dart';
import 'package:skapie/kit_api/host_status.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

const _fakeRuntime = ResolvedAgentRuntime(presetId: 'fake', useFake: true);

class _ReadGrant implements RepositoryPermission {
  const _ReadGrant();
  @override
  Future<String?> chooseDirectory() async => null;
  @override
  Future<bool> canRead(String path) async => true;
}

class _WriteGrant implements PatchWritePermission {
  const _WriteGrant();
  @override
  Future<String?> chooseDirectory() async => null;
  @override
  Future<bool> canWrite(String path) async => true;
  @override
  Future<String?> exportProposal({
    required String name,
    required String text,
  }) async => null;
}

void main() {
  test('13.3.1 a broken kit.json shows a package fault and clears when fixed', () async {
    final root = await Directory.systemTemp.createTemp('skapie_status_');
    addTearDown(() => root.delete(recursive: true));
    final registry = createBuiltinRegistry();
    final status = HostStatusLog();
    final api = createAppKitApi(
      store: SceneStore(),
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
      status: status,
    );

    final dir = Directory('${root.path}/demo.bad');
    await dir.create(recursive: true);
    final file = File('${dir.path}/kit.json');
    await file.writeAsString('{"schemaVersion":1,"id":"demo.bad"}');

    await api.reloadPackages();
    expect(status.hasErrors, isTrue);
    expect(
      status.items.map((item) => item.key),
      contains('package:demo.bad'),
    );

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'id': 'demo.bad',
        'displayName': 'Fixed',
        'objects': [
          {'typeId': 'box', 'x': 0, 'y': 0, 'width': 40, 'height': 20},
        ],
      }),
    );
    await api.reloadPackages();
    expect(status.hasErrors, isFalse);
  });

  test('13.3.2 a tool denial shows, and a later success clears it', () async {
    final repo = await Directory.systemTemp.createTemp('skapie_status_');
    addTearDown(() => repo.delete(recursive: true));
    await File('${repo.path}/greeting.txt').writeAsString('hello\n');

    final status = HostStatusLog();
    final api = createAppKitApi(store: SceneStore(), status: status);
    addCodingWorkflowStarter(api, origin: Offset.zero);
    final repository = api.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == codingRepositoryKitId &&
          object.props[skapieRoleProp] == 'frame',
    );
    final llmBody = api.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == harnessLlmKitId &&
          object.props[skapieRoleProp] == 'body',
    );
    api.updateProps(repository.id, {repositoryPathProp: repo.path});

    AgentController controller() => AgentController(
      kitApi: api,
      session: AgentSession(
        model: ScriptedAgentModel([
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 'c1',
                name: 'edit',
                argumentsJson:
                    '{"path":"greeting.txt","oldText":"hello","newText":"hi"}',
              ),
            ],
          ),
          const AgentModelReply(content: 'Done.'),
        ]),
        kitApi: api,
      ),
      runtime: _fakeRuntime,
      repositoryPermission: const _ReadGrant(),
      writePermission: const _WriteGrant(),
    );

    await controller().sendUser('Edit it', targetBodyId: llmBody.id);
    expect(
      status.items.map((item) => item.key),
      contains('tool:edit'),
    );

    api.updateProps(repository.id, {
      repositoryPathProp: repo.path,
      repositoryWritePathProp: repo.path,
    });
    await controller().sendUser('Edit it', targetBodyId: llmBody.id);
    expect(
      status.items.map((item) => item.key),
      isNot(contains('tool:edit')),
    );
    expect(await File('${repo.path}/greeting.txt').readAsString(), 'hi\n');
  });
}
