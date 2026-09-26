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

  SceneObject frame(String kitId) => kitApi.store.document.objects.singleWhere(
    (object) =>
        object.props[skapieKitProp] == kitId &&
        object.props[skapieRoleProp] == 'frame',
  );

  SceneObject body(String kitId) => kitApi.store.document.objects.singleWhere(
    (object) =>
        object.props[skapieKitProp] == kitId &&
        object.props[skapieRoleProp] == 'body',
  );

  test('starter places public kits and explains all 21 ordinary cables', () {
    final bounds = addCodingWorkflowStarter(
      kitApi,
      origin: const Offset(30, 50),
    );
    expect(bounds.topLeft, const Offset(30, 50));
    final document = kitApi.store.document;
    final frames = document.objects
        .where((object) => object.props[skapieRoleProp] == 'frame')
        .toList();
    expect(frames, hasLength(17));
    for (final placed in frames) {
      expect(kitApi.getKit(placed.props[skapieKitProp] as String), isNotNull);
    }
    expect(frame(boardTextKitId).props[kitNameProp], 'Task Text');
    expect(body(boardTextKitId).props['content'], isEmpty);
    expect(frame(proposePatchKitId).props[skapieKitProp], proposePatchKitId);
    expect(
      frame(codingPatchProposalKitId).props[kitNameProp],
      'Patch Proposal',
    );
    expect(
      frame(codingReviewDecisionKitId).props[kitNameProp],
      'Review Decision',
    );
    expect(frame(codingWriteScopeKitId).props[kitNameProp], 'Write Scope');
    expect(frame(codingApplyPatchKitId).props[kitNameProp], 'Apply Patch');
    expect(frame(codingCheckSpecKitId).props[kitNameProp], 'Check Spec');
    expect(frame(codingRunCheckKitId).props[kitNameProp], 'Run Check');
    expect(frame(codingCheckResultKitId).props[kitNameProp], 'Check Result');

    final cables = sceneCables(document);
    expect(cables, hasLength(21));
    for (final cable in cables) {
      expect(kitPortsConnect(cable.fromKind!, cable.toKind!), isTrue);
      expect(describeConnection(document, cable).explanation, isNotEmpty);
    }
    expect(
      cables.where((cable) => cable.toKind == KitPortKind.llmContext),
      isEmpty,
    );
    expect(frame(codingRepositoryKitId).props[repositoryPathProp], isEmpty);
    expect(frame(codingWriteScopeKitId).props[writeScopePathProp], isEmpty);
    expect(frame(codingCheckSpecKitId).props[checkPresetProp], isEmpty);
    expect(body(codingPatchProposalKitId).props['content'], 'No proposal yet');
    expect(body(codingReviewDecisionKitId).props[reviewDecisionProp], isEmpty);
    expect(body(codingCheckResultKitId).props['checkOutcome'], isEmpty);
    expect(kitApi.store.canUndo, isTrue);
    expect(
      () => addCodingWorkflowStarter(kitApi, origin: Offset.zero),
      throwsStateError,
    );
  });

  test(
    'a later manual turn keeps Conversation and may add check context',
    () async {
      addCodingWorkflowStarter(kitApi, origin: Offset.zero);
      kitApi.updateProps(body(boardTextKitId).id, {
        'content': 'Inspect and change one function.',
      });
      final llmBody = body(harnessLlmKitId);
      final controller = AgentController(
        kitApi: kitApi,
        session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
        runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      );
      expect(
        llmConversationHistory(kitApi.store.document, llmBody.id),
        isEmpty,
      );
      expect(body(codingCheckResultKitId).props['content'], 'No check run yet');

      await controller.sendUser(
        llmCableInput(kitApi.store.document, llmBody.id),
        targetBodyId: llmBody.id,
      );
      final firstHistory = llmConversationHistory(
        kitApi.store.document,
        llmBody.id,
      );
      expect(firstHistory, hasLength(2));
      expect(body(codingCheckResultKitId).props['content'], 'No check run yet');

      final ports = kitPorts(kitApi.store.document);
      connectKitPorts(
        kitApi: kitApi,
        from: ports.singleWhere(
          (port) =>
              port.frameId == frame(codingCheckResultKitId).id &&
              port.kind == KitPortKind.checkResultOut,
        ),
        to: ports.singleWhere(
          (port) =>
              port.frameId == frame(harnessLlmKitId).id &&
              port.kind == KitPortKind.llmContext,
        ),
      );
      kitApi.updateProps(body(codingCheckResultKitId).id, {
        'content': 'Check failed: fix the changed line.',
      });
      expect(
        llmContextText(kitApi.store.document, llmBody.id),
        contains('Check failed'),
      );
      expect(
        llmConversationHistory(kitApi.store.document, llmBody.id),
        firstHistory,
      );
      await controller.sendUser('Revise the patch', targetBodyId: llmBody.id);
      expect(
        llmConversationHistory(kitApi.store.document, llmBody.id),
        hasLength(4),
      );
      expect(
        body(codingCheckResultKitId).props['content'],
        contains('Check failed'),
      );
    },
  );
}
