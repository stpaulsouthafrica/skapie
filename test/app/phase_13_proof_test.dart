import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/app/coding_workflow_starter.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/host_status.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/kit_api/kit_seed.dart';
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

AgentController _controller(KitApi api, AgentModel model) {
  return AgentController(
    kitApi: api,
    session: AgentSession(model: model, kitApi: api),
    runtime: _fakeRuntime,
    repositoryPermission: const _ReadGrant(),
    writePermission: const _WriteGrant(),
  );
}

Future<KitApi> _seededShelf(
  Directory shelf, {
  HostStatusLog? status,
}) async {
  final registry = createBuiltinRegistry();
  final store = KitPackageStore(root: shelf, registry: registry);
  await seedStarterKits(store);
  final api = createAppKitApi(
    store: SceneStore(),
    registry: registry,
    packages: store,
    status: status,
  );
  await api.reloadPackages();
  return api;
}

SceneObject _object(KitApi api, String kitId, {String role = 'frame'}) {
  return api.store.document.objects.firstWhere(
    (object) =>
        object.props[skapieKitProp] == kitId &&
        object.props[skapieRoleProp] == role,
  );
}

void main() {
  test('13.5.1 an empty board still runs a trivial completion', () async {
    final shelf = await Directory.systemTemp.createTemp('skapie_shelf_');
    addTearDown(() => shelf.delete(recursive: true));
    final api = await _seededShelf(shelf);

    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final task = api.instantiate(boardTextKitId, origin: const Offset(-400, 0));
    final output = api.instantiate(boardTextKitId, origin: const Offset(500, 0));
    api.updateProps(task.last, {'content': 'Say hello'});
    connectTextToLlm(
      kitApi: api,
      textObjectId: task.first,
      llmBodyId: llm.last,
    );
    connectLlmOutput(
      kitApi: api,
      sourceBodyId: llm.last,
      targetBodyId: output.first,
      port: llmTextOutPort,
    );

    await _controller(
      api,
      FakeAgentModel(),
    ).sendUser('Say hello', targetBodyId: llm.last);

    expect(
      api.store.document.objectById(llm.last)!.props['content'],
      contains('Echo: Say hello'),
    );
  });

  test('13.5.2 the seeded starter completes one repo edit', () async {
    final shelf = await Directory.systemTemp.createTemp('skapie_shelf_');
    final repo = await Directory.systemTemp.createTemp('skapie_repo_');
    addTearDown(() => shelf.delete(recursive: true));
    addTearDown(() => repo.delete(recursive: true));
    final file = File('${repo.path}/greeting.txt');
    await file.writeAsString('hello\n');

    final api = await _seededShelf(shelf);
    addCodingWorkflowStarter(api, origin: Offset.zero);
    final repository = _object(api, codingRepositoryKitId);
    api.updateProps(repository.id, {
      repositoryPathProp: repo.path,
      repositoryWritePathProp: repo.path,
    });
    final task = api.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == boardTextKitId &&
          object.props[skapieRoleProp] == 'body' &&
          object.y < 400,
    );
    api.updateProps(task.id, {'content': 'Change greeting to hi'});
    final llmBody = _object(api, harnessLlmKitId, role: 'body');

    await _controller(
      api,
      ScriptedAgentModel([
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
    ).sendUser('Change greeting to hi', targetBodyId: llmBody.id);

    expect(await file.readAsString(), 'hi\n');
  });

  test(
    '13.4.2 + 13.5.3 the starter LLM authors a useful kit on the shelf',
    () async {
      final shelf = await Directory.systemTemp.createTemp('skapie_shelf_');
      addTearDown(() => shelf.delete(recursive: true));
      final status = HostStatusLog();
      final api = await _seededShelf(shelf, status: status);
      addCodingWorkflowStarter(api, origin: Offset.zero);
      final repository = _object(api, codingRepositoryKitId);
      api.updateProps(repository.id, {
        repositoryPathProp: shelf.path,
        repositoryWritePathProp: shelf.path,
      });
      final llmBody = _object(api, harnessLlmKitId, role: 'body');

      const checklist = 'Always read the diff before you edit.';
      final kitJson = jsonEncode({
        'schemaVersion': 1,
        'id': 'demo.checklist',
        'displayName': 'Checklist',
        'ports': [
          {'id': 'out', 'value': 'text', 'flow': 'output', 'label': 'Docs'},
        ],
        'assets': ['checklist.txt'],
        'objects': [
          {
            'typeId': 'box',
            'x': 0,
            'y': 0,
            'width': 220,
            'height': 120,
            'props': {
              skapieKitProp: 'demo.checklist',
              skapieRoleProp: 'frame',
            },
          },
          {
            'typeId': 'text',
            'x': 12,
            'y': 40,
            'width': 196,
            'height': 48,
            'props': {
              skapieKitProp: 'demo.checklist',
              skapieRoleProp: 'body',
              'contentRef': 'checklist.txt',
            },
          },
        ],
      });

      await _controller(
        api,
        ScriptedAgentModel([
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 's1',
                name: 'shell',
                argumentsJson: '{"command":"mkdir -p demo.checklist"}',
              ),
            ],
          ),
          AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 'w1',
                name: 'write',
                argumentsJson: jsonEncode({
                  'path': 'demo.checklist/kit.json',
                  'content': kitJson,
                }),
              ),
            ],
          ),
          AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 'w2',
                name: 'write',
                argumentsJson: jsonEncode({
                  'path': 'demo.checklist/checklist.txt',
                  'content': checklist,
                }),
              ),
            ],
          ),
          const AgentModelReply(content: 'Authored demo.checklist.'),
        ]),
      ).sendUser('Author a checklist kit on the shelf', targetBodyId: llmBody.id);

      expect(
        File('${shelf.path}/demo.checklist/kit.json').existsSync(),
        isTrue,
      );
      expect(
        await File('${shelf.path}/demo.checklist/checklist.txt').readAsString(),
        checklist,
      );

      await api.reloadPackages();
      expect(api.getKit('demo.checklist'), isNotNull);

      final ids = api.instantiate(
        'demo.checklist',
        origin: const Offset(1500, 0),
      );
      connectTextToLlm(
        kitApi: api,
        textObjectId: ids.first,
        llmBodyId: llmBody.id,
        port: llmContextPort,
      );
      final assembly = assembleContext(
        kitApi: api,
        llmBodyId: llmBody.id,
        taskInput: '',
      );
      expect(
        assembly.itemsFor(ContextLayer.instructions).map((item) => item.text),
        contains(checklist),
      );
      expect(status.hasErrors, isFalse);
    },
  );
}
