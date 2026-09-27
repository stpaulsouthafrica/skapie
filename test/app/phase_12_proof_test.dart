import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/coding_workflow_starter.dart';
import 'package:skapie/canvas/kit_ports.dart';
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
  test('12.5.1 an empty board runs a trivial completion with LLM + Text', () async {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final task = kitApi.instantiate(boardTextKitId, origin: const Offset(-400, 0));
    final output = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(500, 0),
    );
    kitApi.updateProps(task.last, {'content': 'Say hello'});
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: task.first,
      llmBodyId: llm.last,
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: output.first,
      port: llmTextOutPort,
    );
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: _fakeRuntime,
    );

    await controller.sendUser('Say hello', targetBodyId: llm.last);

    final body = kitApi.store.document.objectById(llm.last)!;
    expect(body.props['content'], contains('Echo: Say hello'));
    expect(controller.runningBodyId, isNull);
  });

  test('12.5.2 the starter completes one edit through Read + Edit', () async {
    final repo = await Directory.systemTemp.createTemp('skapie-edit-');
    addTearDown(() => repo.delete(recursive: true));
    final file = File('${repo.path}/greeting.txt');
    await file.writeAsString('hello\n');

    final kitApi = createAppKitApi(store: SceneStore());
    addCodingWorkflowStarter(kitApi, origin: Offset.zero);
    final repository = kitApi.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == codingRepositoryKitId &&
          object.props[skapieRoleProp] == 'frame',
    );
    kitApi.updateProps(repository.id, {
      repositoryPathProp: repo.path,
      repositoryWritePathProp: repo.path,
    });
    final task = kitApi.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == boardTextKitId &&
          object.props[skapieRoleProp] == 'body' &&
          object.y < 400,
    );
    kitApi.updateProps(task.id, {'content': 'Change greeting to hi'});
    final llmBody = kitApi.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == harnessLlmKitId &&
          object.props[skapieRoleProp] == 'body',
    );

    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(
        model: ScriptedAgentModel([
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 'c1',
                name: 'read',
                argumentsJson: '{"action":"read","path":"greeting.txt"}',
              ),
            ],
          ),
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 'c2',
                name: 'edit',
                argumentsJson:
                    '{"path":"greeting.txt","oldText":"hello","newText":"hi"}',
              ),
            ],
          ),
          const AgentModelReply(content: 'Done.'),
        ]),
        kitApi: kitApi,
      ),
      runtime: _fakeRuntime,
      repositoryPermission: const _ReadGrant(),
      writePermission: const _WriteGrant(),
    );

    await controller.sendUser('Change greeting to hi', targetBodyId: llmBody.id);

    expect(
      controller.toolActivitiesFor(llmBody.id).map((item) => item.name),
      containsAll(['read', 'edit']),
    );
    expect(await file.readAsString(), 'hi\n');
  });

  test('12.4.2 the Extensions kit points at bundled local docs', () {
    for (final path in [
      'docs/kit_author.md',
      'docs/kit_api.md',
      'docs/kit_packages.md',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(skapieExtensionsBody, contains('kit.json'));
    expect(skapieExtensionsBody, contains('schemaVersion'));
    expect(skapieExtensionsBody, contains('docs/kit_author.md'));
    expect(skapieExtensionsBody, isNot(contains('http')));
  });

  test('12.5.3 a package is authored, reloaded, and placed with no lib change', () async {
    final root = await Directory.systemTemp.createTemp('skapie-kits-');
    addTearDown(() => root.delete(recursive: true));
    final registry = createBuiltinRegistry();
    final kitApi = createAppKitApi(
      store: SceneStore(),
      registry: registry,
      packages: KitPackageStore(root: root, registry: registry),
    );

    await kitApi.saveKit(
      const KitRecipe(
        id: 'user.note',
        displayName: 'User Note',
        objects: [
          KitObjectSpec(
            typeId: boxTypeId,
            x: 0,
            y: 0,
            width: 200,
            height: 80,
            props: {skapieKitProp: 'user.note', skapieRoleProp: 'frame'},
          ),
          KitObjectSpec(
            typeId: textTypeId,
            x: 12,
            y: 16,
            width: 176,
            height: 48,
            props: {
              skapieKitProp: 'user.note',
              skapieRoleProp: 'body',
              'content': 'Note',
            },
          ),
        ],
      ),
    );
    expect(File('${root.path}/user.note/kit.json').existsSync(), isTrue);

    await kitApi.reloadPackages();
    expect(kitApi.getKit('user.note'), isNotNull);

    final ids = kitApi.instantiate('user.note', origin: Offset.zero);
    expect(ids, hasLength(2));
    expect(
      kitApi.store.document.objectById(ids.first)!.props[skapieKitProp],
      'user.note',
    );
  });
}
