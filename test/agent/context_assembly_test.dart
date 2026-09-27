import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

void main() {
  late KitApi api;

  setUp(() => api = createAppKitApi(includeDemotedKits: true, store: SceneStore()));

  test('each request source keeps its kit and provenance', () {
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final task = api.instantiate(boardTextKitId, origin: const Offset(400, 0));
    final instructions = api.instantiate(
      boardTextKitId,
      origin: const Offset(400, 200),
    );
    final tool = api.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 400),
    );
    api.updateProps(task.last, {'content': 'Add a text kit'});
    api.updateProps(instructions.last, {'content': 'Be careful'});
    connectTextToLlm(
      kitApi: api,
      textObjectId: task.first,
      llmBodyId: llm.last,
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: instructions.first,
      llmBodyId: llm.last,
      port: llmContextPort,
    );
    attachToolKit(kitApi: api, toolObjectId: tool.first, llmBodyId: llm.last);

    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'Add a text kit',
    );

    final taskItem = assembly.itemsFor(ContextLayer.task).single;
    expect(taskItem.sourceKitId, boardTextKitId);
    expect(taskItem.provenance, ContextProvenance.userTask);
    expect(taskItem.text, 'Add a text kit');

    final instructionItem = assembly.itemsFor(ContextLayer.instructions).single;
    expect(instructionItem.sourceKitId, boardTextKitId);
    expect(instructionItem.provenance, ContextProvenance.boardInstruction);
    expect(assembly.instructionText, 'Be careful');

    final toolItem = assembly.itemsFor(ContextLayer.tools).single;
    expect(toolItem.sourceRange, 'tools.list_kits');
    expect(toolItem.provenance, ContextProvenance.toolDefinition);
    expect(assembly.tools.map((tool) => tool.name), contains('list_kits'));
  });

  test('disconnected Conversation drops history and names the reason', () {
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final conversation = api.instantiate(
      harnessConversationKitId,
      origin: const Offset(400, 0),
    );
    final connected = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'hello',
    );
    expect(
      connected.exclusions.any(
        (item) => item.reason == 'Not cabled to Conversation',
      ),
      isTrue,
    );

    connectTextToLlm(
      kitApi: api,
      textObjectId: conversation.first,
      llmBodyId: llm.last,
      port: llmConversationPort,
    );
    api.updateProps(conversation.last, {
      'turns': [
        {'role': 'user', 'content': 'first'},
        {'role': 'assistant', 'content': 'second'},
      ],
    });

    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'hello',
    );
    expect(assembly.history.map((turn) => turn.content), ['first', 'second']);
    expect(assembly.itemsFor(ContextLayer.history), hasLength(2));
    expect(
      assembly.exclusions.any(
        (item) => item.reason == 'Not cabled to Conversation',
      ),
      isFalse,
    );
  });

  test('repository text is never attached without a read tool', () {
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final repository = api.instantiate(
      codingRepositoryKitId,
      origin: const Offset(400, 0),
    );
    api.updateProps(repository.first, {repositoryPathProp: '/example'});

    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'hello',
    );
    expect(assembly.itemsFor(ContextLayer.excerpts), isEmpty);
    expect(
      assembly.exclusions.any(
        (item) =>
            item.reason ==
            'Repository root only; no file text is sent unless a read tool runs',
      ),
      isTrue,
    );
  });

  test('older turns past the budget are omitted with a reason', () {
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final conversation = api.instantiate(
      harnessConversationKitId,
      origin: const Offset(400, 0),
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: conversation.first,
      llmBodyId: llm.last,
      port: llmConversationPort,
    );
    final big = 'x' * (contextHistoryCharBudget ~/ 2);
    api.updateProps(conversation.last, {
      'turns': [
        {'role': 'user', 'content': big},
        {'role': 'assistant', 'content': big},
        {'role': 'user', 'content': big},
      ],
    });

    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'hello',
    );
    expect(assembly.history, hasLength(2));
    expect(
      assembly.exclusions.any((item) => item.reason.contains('older turns')),
      isTrue,
    );
  });
}
