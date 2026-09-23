import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/world/kits.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  List<String> llmKit() =>
      kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);

  List<String> textKit(Offset origin, {String content = 'hello'}) {
    final ids = kitApi.instantiate(boardTextKitId, origin: origin);
    kitApi.updateProps(ids.last, {'content': content});
    return ids;
  }

  void sink(List<String> llm) {
    final reply = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(600, 0),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: reply.first,
      port: llmTextOutPort,
    );
  }

  BoardValidation check() => validateBoard(kitApi.store.document);

  test('each issue points at the ports it is about', () {
    final llm = llmKit();
    final result = check();
    final input = result.issues.firstWhere((i) => i.message == 'Needs input');
    final sinkIssue = result.issues.firstWhere(
      (i) => i.message == 'Needs Output or Conversation',
    );
    expect(boardIssuePorts(kitApi.store.document, input).map((p) => p.kind), [
      KitPortKind.llmInput,
    ]);
    expect(
      boardIssuePorts(kitApi.store.document, sinkIssue).map((p) => p.kind),
      unorderedEquals([KitPortKind.llmConversation, KitPortKind.llmOutput]),
    );
    expect(
      boardIssuePorts(
        kitApi.store.document,
        input,
      ).every((port) => port.frameId == llm.first),
      isTrue,
    );
    expect(boardIssueKey(input), isNot(boardIssueKey(sinkIssue)));
  });

  test('a reply loop points at the ports on both ends of its cable', () {
    final a = llmKit();
    final b = kitApi.instantiate(harnessLlmKitId, origin: const Offset(500, 0));
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: a.last,
      targetBodyId: b.last,
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: b.last,
      targetBodyId: a.last,
    );
    final loop = check().issues.firstWhere(
      (i) => i.kind == BoardIssueKind.cycle,
    );
    expect(
      boardIssuePorts(kitApi.store.document, loop).map((p) => p.kind),
      unorderedEquals([KitPortKind.llmOutput, KitPortKind.llmInput]),
    );
  });

  test('Text Out → LLM Tools is refused with a reason', () {
    expect(kitPortsConnect(KitPortKind.textOut, KitPortKind.llmTools), isFalse);
    expect(
      kitPortRefusal(KitPortKind.textOut, KitPortKind.llmTools),
      'Tools takes Tool, not Text',
    );
    expect(kitPortRefusal(KitPortKind.textOut, KitPortKind.llmInput), isNull);
    expect(
      kitPortRefusal(KitPortKind.textOut, KitPortKind.llmOutput),
      'Connect an output to an input',
    );
  });

  test('a saved link with the wrong type is drawn invalid and blocks Run', () {
    final llm = llmKit();
    final text = textKit(const Offset(-400, 0));
    sink(llm);
    addKitLink(
      kitApi: kitApi,
      objectId: text.first,
      to: llm.last,
      port: llmToolsPort,
    );
    final result = check();
    expect(
      sceneCables(kitApi.store.document).where((c) => c.port == llmToolsPort),
      isEmpty,
    );
    final marked = result.markedCables.single;
    expect(marked.kind, BoardIssueKind.incompatible);
    expect(marked.cable.ownerId, text.first);
    expect(
      result.runBlockers(llm.last).map((issue) => issue.kind),
      contains(BoardIssueKind.incompatible),
    );
  });

  test('a read tool with no Repository says the grant is missing', () {
    final llm = llmKit();
    sink(llm);
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: textKit(const Offset(-400, 0)).first,
      llmBodyId: llm.last,
    );
    final tool = kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: const Offset(-400, 300),
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );

    var blockers = check().runBlockers(llm.last);
    expect(blockers.single.kind, BoardIssueKind.missingGrant);
    expect(blockers.single.message, 'Repository grant missing');
    expect(blockers.single.frameId, tool.first);

    final repository = kitApi.instantiate(
      codingRepositoryKitId,
      origin: const Offset(-800, 300),
    );
    connectRepositoryToTool(
      kitApi: kitApi,
      repositoryFrameId: repository.first,
      toolFrameId: tool.first,
    );
    blockers = check().runBlockers(llm.last);
    expect(blockers.single.message, 'Repository has no folder');
    expect(blockers.single.frameId, repository.first);

    kitApi.updateProps(repository.first, {repositoryPathProp: '/tmp/repo'});
    expect(check().runBlockers(llm.last), isEmpty);
  });

  test('an unattached tool without a grant only warns', () {
    kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: const Offset(-400, 300),
    );
    final issue = check().issues.single;
    expect(issue.kind, BoardIssueKind.missingGrant);
    expect(issue.severity, BoardIssueSeverity.warning);
  });

  test(
    'deleting a cabled kit leaves a visible stale end, and undo restores',
    () {
      final llm = llmKit();
      final text = textKit(const Offset(-400, 0));
      connectTextToLlm(
        kitApi: kitApi,
        textObjectId: text.first,
        llmBodyId: llm.last,
      );
      removeKitSelection(kitApi: kitApi, selectedId: llm.first);

      expect(sceneCables(kitApi.store.document), isEmpty);
      final result = check();
      final stale = result.markedCables.single;
      expect(stale.kind, BoardIssueKind.staleEndpoint);
      expect(stale.dangling, CableDangling.end);
      expect(stale.cable.ownerId, text.first);
      expect(
        result.issues.single.message,
        'Out points at a kit that was deleted',
      );

      kitApi.store.undo();
      expect(kitApi.store.document.objectById(llm.first), isNotNull);
      expect(kitApi.store.document.objectById(llm.last), isNotNull);
      expect(sceneCables(kitApi.store.document), hasLength(1));
      expect(check().markedCables, isEmpty);
    },
  );

  test('a stale Output end blocks the LLM that owns it', () {
    final llm = llmKit();
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: textKit(const Offset(-400, 0)).first,
      llmBodyId: llm.last,
    );
    final reply = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(600, 0),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: reply.first,
      port: llmTextOutPort,
    );
    removeKitSelection(kitApi: kitApi, selectedId: reply.first);
    final blockers = check().runBlockers(llm.last);
    expect(
      blockers.map((issue) => issue.kind),
      containsAll([BoardIssueKind.staleEndpoint, BoardIssueKind.missingInput]),
    );
  });

  test('Run with an empty Input says so, unless the prompt is supplied', () {
    final llm = llmKit();
    sink(llm);
    expect(check().runBlockers(llm.last).single.message, 'Needs input');
    expect(check().runBlockers(llm.last, inputSupplied: true), isEmpty);

    final text = textKit(const Offset(-400, 0), content: '  ');
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    expect(check().runBlockers(llm.last).single.message, 'Input is empty');
    kitApi.updateProps(text.last, {'content': 'hello'});
    expect(check().runBlockers(llm.last), isEmpty);
  });

  test('a missing Output or Conversation blocks Run', () {
    final llm = llmKit();
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: textKit(const Offset(-400, 0)).first,
      llmBodyId: llm.last,
    );
    expect(
      check().runBlockers(llm.last).single.message,
      'Needs Output or Conversation',
    );
  });

  test('one undo restores a cut valid cable', () {
    final llm = llmKit();
    final text = textKit(const Offset(-400, 0));
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    final cable = sceneCables(kitApi.store.document).single;
    disconnectSceneCable(kitApi: kitApi, cable: cable);
    expect(sceneCables(kitApi.store.document), isEmpty);
    kitApi.store.undo();
    expect(sceneCables(kitApi.store.document).single.id, cable.id);
    expect(check().markedCables, isEmpty);
  });

  test('a one-cable port with two saved cables marks the extra', () {
    final tool = kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: const Offset(-400, 300),
    );
    for (final y in [0.0, 300.0]) {
      final repository = kitApi.instantiate(
        codingRepositoryKitId,
        origin: Offset(-800, y),
      );
      kitApi.updateProps(repository.first, {repositoryPathProp: '/tmp/r$y'});
      addKitLink(
        kitApi: kitApi,
        objectId: repository.first,
        to: tool.first,
        port: repositoryPort,
      );
    }
    final result = check();
    final extra = result.markedCables.single;
    expect(extra.kind, BoardIssueKind.tooMany);
    expect(result.issues.single.message, 'Repository takes one cable, not 2');
  });

  test('LLM replies feeding each other are a loop; a text loop is not', () {
    final a = llmKit();
    final b = kitApi.instantiate(harnessLlmKitId, origin: const Offset(500, 0));
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: a.last,
      targetBodyId: b.last,
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: b.last,
      targetBodyId: a.last,
    );
    var result = check();
    final loops = [
      for (final issue in result.issues)
        if (issue.kind == BoardIssueKind.cycle) issue,
    ];
    expect(loops, hasLength(1));
    expect(loops.single.blocks, {a.last, b.last});
    expect(
      result.markedCables.where((m) => m.kind == BoardIssueKind.cycle),
      hasLength(2),
    );

    disconnectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: b.last,
      targetBodyId: a.last,
      port: llmInputPort,
    );
    final text = textKit(const Offset(-400, 0));
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: a.last,
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: a.last,
      targetBodyId: text.first,
      port: llmTextOutPort,
    );
    result = check();
    expect(result.issues.where((i) => i.kind == BoardIssueKind.cycle), isEmpty);
    expect(result.runBlockers(a.last), isEmpty);
  });
}
