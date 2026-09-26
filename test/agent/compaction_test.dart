import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/compaction.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

void main() {
  late KitApi api;

  setUp(() => api = createAppKitApi(store: SceneStore()));

  test('compaction replaces a turn span but keeps the original turns', () {
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
    api.updateProps(conversation.last, {
      'turns': [
        {'role': 'user', 'content': 'first paste'},
        {'role': 'assistant', 'content': 'first reply'},
        {'role': 'user', 'content': 'second paste'},
        {'role': 'assistant', 'content': 'second reply'},
      ],
    });

    expect(
      compactOldestTurns(
        kitApi: api,
        bodyId: conversation.last,
        turns: conversationTurnsOf(
          api.store.document.objectById(conversation.last)!,
        ),
        keep: 2,
      ),
      true,
    );
    final body = api.store.document.objectById(conversation.last)!;
    final compaction = conversationCompactionOf(body)!;
    expect(compaction.fromTurn, 0);
    expect(compaction.toTurn, 2);
    expect(compaction.summary, contains('first paste'));
    expect(conversationTurnsOf(body), hasLength(4));

    final history = llmConversationHistory(api.store.document, llm.last);
    expect(history, hasLength(3));
    expect(history.first.content, compaction.summary);
    expect(history.last.content, 'second reply');

    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'go',
    );
    final summaryItem = assembly.itemsFor(ContextLayer.history).first;
    expect(summaryItem.provenance, ContextProvenance.compactedSummary);
    expect(
      assembly.exclusions.any(
        (item) => item.reason.contains('condensed; originals remain'),
      ),
      isTrue,
    );

    clearConversationCompaction(kitApi: api, bodyId: conversation.last);
    expect(llmConversationHistory(api.store.document, llm.last), hasLength(4));
  });

  test('clearing turns also clears a compaction, so nothing is hidden', () {
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
    api.updateProps(conversation.last, {
      'turns': [
        {'role': 'user', 'content': 'old ask'},
        {'role': 'assistant', 'content': 'old answer'},
        {'role': 'user', 'content': 'another ask'},
        {'role': 'assistant', 'content': 'another answer'},
      ],
    });
    expect(
      compactOldestTurns(
        kitApi: api,
        bodyId: conversation.last,
        turns: conversationTurnsOf(
          api.store.document.objectById(conversation.last)!,
        ),
        keep: 2,
      ),
      true,
    );

    clearConversation(kitApi: api, bodyId: conversation.last);
    api.updateProps(conversation.last, {
      'turns': [
        {'role': 'user', 'content': 'new ask'},
        {'role': 'assistant', 'content': 'new answer'},
      ],
    });

    final history = llmConversationHistory(api.store.document, llm.last);
    expect(history.map((turn) => turn.content), ['new ask', 'new answer']);
  });

  test('a read result becomes a bounded excerpt with a line range', () {    final excerpt = contextExcerptFromRead(
      callId: 'c1',
      toolName: 'repo_read_file',
      result: const {
        'ok': true,
        'path': 'lib/main.dart',
        'startLine': 10,
        'endLine': 14,
        'content': '10: foo\n11: bar',
        'truncated': true,
      },
      sourceKitId: 'tools.repo_read_file',
    )!;
    expect(excerpt.path, 'lib/main.dart');
    expect(excerpt.lineStart, 10);
    expect(excerpt.lineEnd, 14);
    expect(excerpt.sourceRange, 'lib/main.dart:10-14');

    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'go',
      excerpts: [excerpt],
    );
    final item = assembly.itemsFor(ContextLayer.excerpts).single;
    expect(item.provenance, ContextProvenance.repositoryText);
    expect(item.sourceRange, 'lib/main.dart:10-14');
    expect(item.truncated, isTrue);
    expect(item.provenance.trust, contains('cannot grant tools'));

    final irrelevant = contextExcerptFromRead(
      callId: 'c2',
      toolName: 'repo_read_file',
      result: const {'ok': false, 'error': 'missing'},
    );
    expect(irrelevant, isNull);
  });

  test('a run that reads a file keeps a bounded excerpt for the preview',
      () async {
    final root = await Directory.systemTemp.createTemp('skapie-excerpt-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/note.txt').writeAsString('one\ntwo\nthree\n');

    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final repository = api.instantiate(
      codingRepositoryKitId,
      origin: const Offset(0, 400),
    );
    final tool = api.instantiate(
      'tools.repo_read_file',
      origin: const Offset(400, 400),
    );
    final output = api.instantiate(
      boardTextKitId,
      origin: const Offset(800, 0),
    );
    addKitLink(
      kitApi: api,
      objectId: llm.last,
      to: output.first,
      port: llmTextOutPort,
    );
    api.updateProps(repository.first, {repositoryPathProp: root.path});
    addKitLink(
      kitApi: api,
      objectId: repository.first,
      to: tool.first,
      port: repositoryPort,
    );
    attachToolKit(kitApi: api, toolObjectId: tool.first, llmBodyId: llm.last);
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(
        model: ScriptedAgentModel([
          const AgentModelReply(
            content: '',
            toolCalls: [
              AgentToolCall(
                id: 'r1',
                name: 'repo_read_file',
                argumentsJson: '{"path":"note.txt"}',
              ),
            ],
          ),
          const AgentModelReply(content: 'done'),
        ]),
        kitApi: api,
      ),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      repositoryPermission: _GrantedRepository(),
    );

    await controller.sendUser('read note', targetBodyId: llm.last);

    final excerpts = controller.excerptsFor(llm.last);
    expect(excerpts, hasLength(1));
    expect(excerpts.single.path, 'note.txt');
    expect(excerpts.single.lineStart, 1);
    expect(excerpts.single.lineEnd, 3);

    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'read note',
      excerpts: excerpts,
    );
    final item = assembly.itemsFor(ContextLayer.excerpts).single;
    expect(item.sourceRange, 'note.txt:1-3');
    expect(item.provenance, ContextProvenance.repositoryText);
  });

  test('excerpts past the budget are omitted with a reason', () {
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final big = 'x' * (contextExcerptCharBudget ~/ 2);
    final excerpts = [
      for (var i = 0; i < 3; i++)
        ContextExcerpt(
          toolName: 'repo_read_file',
          sourceKitId: 'tools.repo_read_file',
          sourceId: 'c$i',
          text: big,
          path: 'file$i.txt',
          lineStart: 1,
          lineEnd: 5,
        ),
    ];
    final assembly = assembleContext(
      kitApi: api,
      llmBodyId: llm.last,
      taskInput: 'go',
      excerpts: excerpts,
    );
    expect(assembly.itemsFor(ContextLayer.excerpts), hasLength(2));
    expect(assembly.omittedExcerpts, 1);
    expect(assembly.isTruncated, isTrue);
    expect(
      assembly.exclusions.any(
        (item) => item.reason.contains('excerpt budget'),
      ),
      isTrue,
    );
    expect(
      contextProvenancePayload(assembly)['omittedExcerpts'],
      1,
    );
  });
}

class _GrantedRepository implements RepositoryPermission {
  @override
  Future<String?> chooseDirectory() async => null;

  @override
  Future<bool> canRead(String path) async => true;
}
