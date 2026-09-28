import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/coding_workflow_starter.dart';
import 'package:skapie/canvas/connection_info.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late KitApi kitApi;

  setUp(() => kitApi = createAppKitApi(store: SceneStore()));

  SceneObject namedFrame(String name) => kitApi.store.document.objects
      .singleWhere(
        (object) =>
            object.props[skapieRoleProp] == 'frame' &&
            object.props[kitNameProp] == name,
      );

  SceneObject frameOf(String kitId) => kitApi.store.document.objects
      .where(
        (object) =>
            object.props[skapieKitProp] == kitId &&
            object.props[skapieRoleProp] == 'frame',
      )
      .first;

  SceneObject body(String kitId) => kitApi.store.document.objects.singleWhere(
    (object) =>
        object.props[skapieKitProp] == kitId &&
        object.props[skapieRoleProp] == 'body',
  );

  test('starter places the lean set and explains all 12 ordinary cables', () {
    final bounds = addCodingWorkflowStarter(
      kitApi,
      origin: const Offset(30, 50),
    );
    expect(bounds.topLeft, const Offset(30, 50));
    final document = kitApi.store.document;
    final frames = document.objects
        .where((object) => object.props[skapieRoleProp] == 'frame')
        .toList();
    expect(frames, hasLength(10));
    for (final placed in frames) {
      expect(kitApi.getKit(placed.props[skapieKitProp] as String), isNotNull);
    }
    expect(namedFrame('Task').props[skapieKitProp], boardTextKitId);
    expect(namedFrame('Output').props[skapieKitProp], boardTextKitId);
    expect(frameOf(harnessLlmKitId), isNotNull);
    expect(frameOf(harnessConversationKitId), isNotNull);
    expect(frameOf(codingRepositoryKitId), isNotNull);
    expect(frameOf(skapieExtensionsKitId), isNotNull);
    for (final name in ['read', 'write', 'edit', 'shell']) {
      expect(frameOf('tools.$name'), isNotNull, reason: name);
    }
    // No check, review, or run-control kit is on the starter.
    for (final kit in document.objects) {
      final id = kit.props[skapieKitProp]?.toString() ?? '';
      expect(id.startsWith('coding.check'), isFalse);
      expect(id.startsWith('coding.patch'), isFalse);
      expect(id.startsWith('coding.review'), isFalse);
      expect(id.startsWith('coding.apply'), isFalse);
      expect(id, isNot('harness.run_control'));
    }

    final cables = sceneCables(document);
    expect(cables, hasLength(12));
    for (final cable in cables) {
      expect(kitPortsConnect(cable.fromKind!, cable.toKind!), isTrue);
      expect(describeConnection(document, cable).explanation, isNotEmpty);
    }
    final repository = frameOf(codingRepositoryKitId);
    expect(repository.props[repositoryPathProp], isEmpty);
    expect(repository.props[repositoryWritePathProp], isEmpty);
    expect(kitApi.store.canUndo, isTrue);
    expect(
      () => addCodingWorkflowStarter(kitApi, origin: Offset.zero),
      throwsStateError,
    );
  });

  test('a later manual turn keeps Conversation and the Extensions context', () async {
    addCodingWorkflowStarter(kitApi, origin: Offset.zero);
    final task = namedFrame('Task');
    kitApi.updateProps(
      kitApi.store.document.objects.firstWhere(
        (object) =>
            object.props[skapieKitProp] == boardTextKitId &&
            object.props[skapieRoleProp] == 'body' &&
            object.y < 400,
      ).id,
      {'content': 'Change one line.'},
    );
    final llmBody = body(harnessLlmKitId);
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    expect(llmConversationHistory(kitApi.store.document, llmBody.id), isEmpty);
    expect(
      llmContextText(kitApi.store.document, llmBody.id),
      contains('kit.json'),
    );

    await controller.sendUser(
      llmCableInput(kitApi.store.document, llmBody.id),
      targetBodyId: llmBody.id,
    );
    final firstHistory = llmConversationHistory(
      kitApi.store.document,
      llmBody.id,
    );
    expect(firstHistory, hasLength(2));
    expect(task.props[kitNameProp], 'Task');

    await controller.sendUser('Do it', targetBodyId: llmBody.id);
    expect(
      llmConversationHistory(kitApi.store.document, llmBody.id),
      hasLength(4),
    );
  });
}
