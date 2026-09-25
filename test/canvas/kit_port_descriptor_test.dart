import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/world/kits.dart';

void main() {
  test('every port kind has one descriptor with a unique endpoint id', () {
    final specs = [...builtinKitPorts.values, worldToolKitPorts];
    expect({
      for (final list in specs) ...list.map((spec) => spec.kind),
    }, KitPortKind.values.toSet());
    for (final list in specs) {
      final ids = list.map((spec) => spec.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    }
  });

  test('a mixed board keeps every port and cable from saved links', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 0),
    );
    final reply = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(500, 0),
    );
    final conversation = kitApi.instantiate(
      harnessConversationKitId,
      origin: const Offset(500, 200),
    );
    final repository = kitApi.instantiate(
      codingRepositoryKitId,
      origin: const Offset(-800, 400),
    );
    final tool = kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: const Offset(-400, 400),
    );
    kitApi.instantiate(proposePatchKitId, origin: const Offset(-400, 600));
    kitApi.instantiate(codingPatchProposalKitId, origin: const Offset(0, 600));
    kitApi.instantiate(
      codingReviewDecisionKitId,
      origin: const Offset(400, 600),
    );
    kitApi.instantiate(codingApplyPatchKitId, origin: const Offset(800, 600));
    kitApi.instantiate(codingWriteScopeKitId, origin: const Offset(800, 800));
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: reply.first,
      port: llmTextOutPort,
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: conversation.first,
      llmBodyId: llm.last,
      port: llmConversationPort,
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );
    connectRepositoryToTool(
      kitApi: kitApi,
      repositoryFrameId: repository.first,
      toolFrameId: tool.first,
    );

    final document = kitApi.store.document;
    final kinds = kitPorts(document).map((port) => port.kind).toSet();
    expect(kinds, KitPortKind.values.toSet());

    final cables = sceneCables(document);
    SceneCable cableOn(String port) =>
        cables.singleWhere((cable) => cable.port == port);
    final llmFrame = document.objectById(llm.first)!;
    expect(cables, hasLength(5));
    expect(cableOn(llmInputPort).ownerId, text.first);
    expect(cableOn(llmInputPort).to, llmInputCenter(llmFrame));
    expect(cableOn(llmTextOutPort).ownerId, llm.last);
    expect(cableOn(llmTextOutPort).from, llmOutputCenter(llmFrame));
    expect(cableOn(llmTextOutPort).affectsRun, isFalse);
    expect(cableOn(llmConversationPort).ownerId, conversation.first);
    expect(cableOn(llmConversationPort).from, llmConversationCenter(llmFrame));
    expect(cableOn(llmToolsPort).to, llmToolsCenter(llmFrame));
    expect(cableOn(repositoryPort).targetBodyId, tool.first);
    expect(cableOn(llmInputPort).id, '${text.first}|${llm.last}|input');

    expect(document.objectById(text.first)!.props[linksProp], [
      {'to': llm.last, 'port': llmInputPort},
    ]);
    expect(llmConnectionCount(document, llm.last, KitPortKind.llmInput), 1);
    expect(llmConnectionCount(document, llm.last, KitPortKind.llmOutput), 1);
    expect(
      llmConnectionCount(document, llm.last, KitPortKind.llmConversation),
      1,
    );
    expect(llmConnectionCount(document, llm.last, KitPortKind.llmTools), 1);
  });

  test('a dragged Text → LLM Input cable writes the same link as before', () {
    final dragged = createAppKitApi(store: SceneStore());
    final direct = createAppKitApi(store: SceneStore());
    for (final kitApi in [dragged, direct]) {
      kitApi.instantiate(harnessLlmKitId, origin: const Offset(400, 0));
      kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    }
    final ports = kitPorts(dragged.store.document);
    connectKitPorts(
      kitApi: dragged,
      from: ports.firstWhere((port) => port.kind == KitPortKind.textOut),
      to: ports.firstWhere((port) => port.kind == KitPortKind.llmInput),
    );
    final textFrame = direct.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == boardTextKitId &&
          object.props[skapieRoleProp] == 'frame',
    );
    final llmBody = direct.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == harnessLlmKitId &&
          object.props[skapieRoleProp] == 'body',
    );
    connectTextToLlm(
      kitApi: direct,
      textObjectId: textFrame.id,
      llmBodyId: llmBody.id,
    );
    List<Object?> shape(SceneDocument document) {
      final index = {
        for (final (i, object) in document.objects.indexed) object.id: i,
      };
      return [
        for (final object in document.objects)
          {
            ...object.props,
            linksProp: [
              for (final link in kitLinksOf(object))
                {'to': index[link.to], 'port': link.port},
            ],
          },
      ];
    }

    expect(shape(dragged.store.document), shape(direct.store.document));
    expect(
      kitLinksOf(
        dragged.store.document.objects.firstWhere(
          (object) =>
              object.props[skapieKitProp] == boardTextKitId &&
              object.props[skapieRoleProp] == 'frame',
        ),
      ).single.port,
      llmInputPort,
    );
  });

  test('older single-target props still draw their cable', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 0),
    );
    kitApi.updateProps(text.first, {
      connectedToProp: llm.last,
      connectedPortProp: llmContextPort,
    });
    final cable = sceneCables(kitApi.store.document).single;
    expect(cable.port, llmContextPort);
    expect(cable.toKind, KitPortKind.llmContext);
  });

  test('a single-input port keeps only the newest cable', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final first = kitApi.instantiate(
      codingRepositoryKitId,
      origin: const Offset(-800, 0),
    );
    kitApi.instantiate(codingRepositoryKitId, origin: const Offset(-800, 300));
    kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: const Offset(-300, 0),
    );
    final ports = kitPorts(kitApi.store.document);
    final repositories = ports
        .where((port) => port.kind == KitPortKind.repositoryOut)
        .toList();
    final toolInput = ports.firstWhere(
      (port) => port.kind == KitPortKind.toolRepository,
    );
    connectKitPorts(kitApi: kitApi, from: repositories[0], to: toolInput);
    connectKitPorts(kitApi: kitApi, from: repositories[1], to: toolInput);
    final cable = sceneCables(kitApi.store.document).single;
    expect(cable.ownerId, isNot(first.first));
    expect(cable.ownerId, repositories[1].peerId);
  });
}
