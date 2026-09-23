import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/llm_run_use.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/connection_info.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/world/kits.dart';

void main() {
  late KitApi kitApi;
  late List<String> llm;
  late List<String> text;
  late List<String> context;
  late List<String> tool;
  late List<String> other;
  late List<String> repository;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
    llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    text = kitApi.instantiate(boardTextKitId, origin: const Offset(-400, 0));
    kitApi.updateProps(text.last, {'content': 'hello from the card'});
    context = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 200),
    );
    tool = kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: const Offset(-400, 400),
    );
    other = kitApi.instantiate(
      worldToolKitId('list_kits'),
      origin: const Offset(-400, 600),
    );
    repository = kitApi.instantiate(
      codingRepositoryKitId,
      origin: const Offset(-800, 400),
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: context.first,
      llmBodyId: llm.last,
      port: llmContextPort,
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: other.first,
      llmBodyId: llm.last,
    );
    connectRepositoryToTool(
      kitApi: kitApi,
      repositoryFrameId: repository.first,
      toolFrameId: tool.first,
    );
  });

  SceneCable cable(String port, {String? source}) =>
      sceneCables(kitApi.store.document).firstWhere(
        (item) =>
            item.port == port && (source == null || item.sourceId == source),
      );

  ConnectionInfo describe(SceneCable of) =>
      describeConnection(kitApi.store.document, of);

  test('Text → LLM Input is data with a text preview', () {
    final info = describe(cable(llmInputPort));
    expect(info.source, 'Text · Out');
    expect(info.destination, 'LLM · Input');
    expect(info.role, PortRole.data);
    expect(info.roleLabel, 'Data · Text');
    expect(info.preview, 'hello from the card');
  });

  test('Repository → read tool is a grant, not text', () {
    var info = describe(cable(repositoryPort));
    expect(info.role, PortRole.grant);
    expect(info.roleLabel, 'Grant · Repository');
    expect(info.preview, 'No folder chosen. The grant is not live.');
    expect(info.issue, 'Repository has no folder');

    kitApi.updateProps(repository.first, {repositoryPathProp: '/tmp/repo'});
    info = describe(cable(repositoryPort));
    expect(info.preview, 'Read access to /tmp/repo');
    expect(info.issue, isNull);
  });

  test('Tool → LLM Tools offers a capability', () {
    final info = describe(cable(llmToolsPort, source: tool.first));
    expect(info.role, PortRole.capability);
    expect(info.roleLabel, 'Capability · Tool');
    expect(info.preview, startsWith('Offers repo_list_files'));
  });

  test('a stale cable still describes its live end and the problem', () {
    removeKitSelection(kitApi: kitApi, selectedId: llm.first);
    final validation = validateBoard(kitApi.store.document);
    final stale = validation.markedCables
        .firstWhere(
          (marked) =>
              marked.kind == BoardIssueKind.staleEndpoint &&
              marked.cable.ownerId == text.first,
        )
        .cable;
    final info = describeConnection(
      kitApi.store.document,
      stale,
      validation: validation,
    );
    expect(info.source, 'Text · Out');
    expect(info.destination, 'Deleted kit');
    expect(info.issue, 'Out points at a kit that was deleted');
  });

  test('last use appears only on cables that ran in the latest run', () {
    kitApi.updateProps(repository.first, {repositoryPathProp: '/tmp/repo'});
    final started = DateTime(2026, 9, 23, 23, 40);
    final called = started.add(const Duration(seconds: 2));
    final finished = started.add(const Duration(seconds: 5));
    final uses = {
      llm.last: LlmRunUse(
        bodyId: llm.last,
        startedAt: started,
        readPorts: {llmInputPort},
        toolCalls: {tool.first: called},
        finishedAt: finished,
      ),
    };
    LastUse? of(SceneCable item) =>
        cableLastUse(kitApi.store.document, item, uses);

    expect(of(cable(llmInputPort))!.at, started);
    expect(of(cable(llmToolsPort, source: tool.first))!.at, called);
    expect(of(cable(repositoryPort))!.at, called);
    expect(of(cable(llmContextPort)), isNull);
    expect(of(cable(llmToolsPort, source: other.first)), isNull);
    expect(
      lastUseSummary(kitApi.store.document, cable(llmContextPort), uses),
      'Not used in the latest run',
    );
    expect(
      lastUseSummary(kitApi.store.document, cable(llmContextPort), const {}),
      'No run yet this session',
    );
  });
}
