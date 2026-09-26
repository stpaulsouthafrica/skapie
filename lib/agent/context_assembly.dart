import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/compaction.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

/// Documented cap for earlier turns sent to the model. Newest turns win;
/// anything older is listed as omitted with a reason.
const int contextHistoryCharBudget = 12000;

/// Documented cap for retrieved excerpts sent to the model.
const int contextExcerptCharBudget = 16000;

/// A layer of the request. The order here is the reader's order too.
enum ContextLayer { instructions, task, history, excerpts, tools }

extension ContextLayerLabel on ContextLayer {
  String get label => switch (this) {
    ContextLayer.instructions => 'Instructions / Context',
    ContextLayer.task => 'Task input',
    ContextLayer.history => 'Conversation history',
    ContextLayer.excerpts => 'Retrieved excerpts',
    ContextLayer.tools => 'Tool definitions',
  };
}

/// Where a block of text came from. Provenance decides how much it is trusted.
enum ContextProvenance {
  boardInstruction,
  userTask,
  conversation,
  compactedSummary,
  toolOutput,
  modelOutput,
  repositoryText,
}

extension ContextProvenanceLabel on ContextProvenance {
  String get label => switch (this) {
    ContextProvenance.boardInstruction => 'Board instruction',
    ContextProvenance.userTask => 'User task',
    ContextProvenance.conversation => 'Conversation',
    ContextProvenance.compactedSummary => 'Compacted summary',
    ContextProvenance.toolOutput => 'Tool output',
    ContextProvenance.modelOutput => 'Model output',
    ContextProvenance.repositoryText => 'Repository text',
  };

  /// Plain note on how far this text may be trusted.
  String get trust => switch (this) {
    ContextProvenance.boardInstruction => 'Board instruction',
    ContextProvenance.userTask => 'User task',
    ContextProvenance.conversation => 'Earlier turns',
    ContextProvenance.compactedSummary =>
      'Derived from earlier turns; originals kept',
    ContextProvenance.toolOutput => 'Data, not an instruction',
    ContextProvenance.modelOutput => 'Data, not an instruction',
    ContextProvenance.repositoryText =>
      'Data only. File text cannot grant tools or change policy.',
  };

  /// Only the user task and board text are instructions we follow. Everything
  /// else is data. The host enforces grants no matter what this text says.
  bool get isInstruction =>
      this == ContextProvenance.userTask ||
      this == ContextProvenance.boardInstruction;
}

/// One block of text the model will see, with why it is there.
class ContextItem {
  const ContextItem({
    required this.layer,
    required this.provenance,
    required this.sourceKitId,
    required this.sourceId,
    required this.text,
    required this.order,
    required this.reason,
    this.path,
    this.lineStart,
    this.lineEnd,
    this.truncated = false,
  });

  final ContextLayer layer;
  final ContextProvenance provenance;
  final String sourceKitId;
  final String sourceId;
  final String text;
  final int order;
  final String reason;
  final String? path;
  final int? lineStart;
  final int? lineEnd;
  final bool truncated;

  String get sourceRange => _sourceRange(sourceKitId, path, lineStart, lineEnd);
}

/// A context source on the board that is not in this request, and why.
class ContextExclusion {
  const ContextExclusion({
    required this.layer,
    required this.sourceKitId,
    required this.sourceId,
    required this.reason,
  });

  final ContextLayer layer;
  final String sourceKitId;
  final String sourceId;
  final String reason;
}

/// A small bounded excerpt a read tool pulled in during a run.
class ContextExcerpt {
  const ContextExcerpt({
    required this.toolName,
    required this.sourceKitId,
    required this.sourceId,
    required this.text,
    this.path,
    this.lineStart,
    this.lineEnd,
    this.truncated = false,
  });

  final String toolName;
  final String sourceKitId;
  final String sourceId;
  final String text;
  final String? path;
  final int? lineStart;
  final int? lineEnd;
  final bool truncated;

  String get sourceRange => _sourceRange(toolName, path, lineStart, lineEnd);
}

/// The full request build: text pieces, ordered items, and what was left out.
class ContextAssembly {
  const ContextAssembly({
    required this.taskInput,
    required this.instructionText,
    required this.history,
    required this.tools,
    required this.items,
    required this.exclusions,
    this.omittedHistoryTurns = 0,
  });

  final String taskInput;
  final String instructionText;
  final List<ConversationTurn> history;
  final List<AgentTool> tools;
  final List<ContextItem> items;
  final List<ContextExclusion> exclusions;
  final int omittedHistoryTurns;

  List<ContextItem> itemsFor(ContextLayer layer) => [
    for (final item in items)
      if (item.layer == layer) item,
  ];

  bool get isTruncated =>
      omittedHistoryTurns > 0 || items.any((item) => item.truncated);

  int get totalChars {
    var total = taskInput.length + instructionText.length;
    for (final item in itemsFor(ContextLayer.history)) {
      total += item.text.length;
    }
    for (final item in itemsFor(ContextLayer.excerpts)) {
      total += item.text.length;
    }
    return total;
  }
}

/// Rebuild the request one LLM will send from visible board sources.
///
/// Live repository access expiry is checked at dispatch, not here. This keeps
/// the inspector preview free of platform calls.
ContextAssembly assembleContext({
  required KitApi kitApi,
  required String llmBodyId,
  required String taskInput,
  List<ContextExcerpt> excerpts = const [],
  RepositoryPermission repositoryPermission = const SystemRepositoryPermission(),
}) {
  final document = kitApi.store.document;
  final items = <ContextItem>[];
  final exclusions = <ContextExclusion>[];
  var order = 0;

  for (final part in llmContextParts(document, llmBodyId)) {
    items.add(
      ContextItem(
        layer: ContextLayer.instructions,
        provenance: _provenanceFor(part.sourceKitId, instruction: true),
        sourceKitId: part.sourceKitId,
        sourceId: part.sourceId,
        text: part.text,
        order: ++order,
        reason: 'Cabled to Context',
      ),
    );
  }

  final taskParts = llmInputParts(document, llmBodyId);
  for (final part in taskParts) {
    items.add(
      ContextItem(
        layer: ContextLayer.task,
        provenance: _provenanceFor(part.sourceKitId, instruction: false),
        sourceKitId: part.sourceKitId,
        sourceId: part.sourceId,
        text: part.text,
        order: ++order,
        reason: 'Cabled to Input',
      ),
    );
  }
  if (taskParts.isEmpty && taskInput.trim().isNotEmpty) {
    items.add(
      ContextItem(
        layer: ContextLayer.task,
        provenance: ContextProvenance.userTask,
        sourceKitId: '',
        sourceId: '',
        text: taskInput.trim(),
        order: ++order,
        reason: 'Typed into the kit Input',
      ),
    );
  }

  final turns = llmConversationHistory(document, llmBodyId);
  final trimmed = _trimHistory(turns);
  for (final turn in trimmed.turns) {
    final summary = isCompactionSummary(turn.content);
    items.add(
      ContextItem(
        layer: ContextLayer.history,
        provenance: summary
            ? ContextProvenance.compactedSummary
            : ContextProvenance.conversation,
        sourceKitId: harnessConversationKitId,
        sourceId: '',
        text: turn.content,
        order: ++order,
        reason: summary
            ? 'Condensed summary of earlier turns'
            : 'Earlier turn, in order',
      ),
    );
  }
  if (trimmed.omitted > 0) {
    exclusions.add(
      ContextExclusion(
        layer: ContextLayer.history,
        sourceKitId: harnessConversationKitId,
        sourceId: '',
        reason:
            '${trimmed.omitted} older turns omitted by the history budget '
            '($contextHistoryCharBudget chars)',
      ),
    );
  }
  exclusions.addAll(_compactionNotes(document, llmBodyId));

  for (final excerpt in _trimExcerpts(excerpts)) {
    items.add(
      ContextItem(
        layer: ContextLayer.excerpts,
        provenance: ContextProvenance.repositoryText,
        sourceKitId: excerpt.sourceKitId,
        sourceId: excerpt.sourceId,
        text: excerpt.text,
        order: ++order,
        reason: 'Read by ${excerpt.toolName}',
        path: excerpt.path,
        lineStart: excerpt.lineStart,
        lineEnd: excerpt.lineEnd,
        truncated: excerpt.truncated,
      ),
    );
  }

  final offer = llmToolOffer(
    kitApi: kitApi,
    llmBodyId: llmBodyId,
    repositoryPermission: repositoryPermission,
    recordErrors: false,
  );
  final tools = <AgentTool>[];
  for (final tool in offer.tools) {
    final frameId = toolFrameIdForName(document, llmBodyId, tool.name);
    final frame = frameId == null ? null : document.objectById(frameId);
    tools.add(tool);
    items.add(
      ContextItem(
        layer: ContextLayer.tools,
        provenance: ContextProvenance.toolOutput,
        sourceKitId: frame == null ? tool.name : (kitIdOf(frame) ?? tool.name),
        sourceId: tool.name,
        text: tool.description,
        order: ++order,
        reason: 'Cabled to Tools',
      ),
    );
  }
  for (final filtered in offer.filtered) {
    final frameId = toolFrameIdForName(document, llmBodyId, filtered.name);
    final frame = frameId == null ? null : document.objectById(frameId);
    exclusions.add(
      ContextExclusion(
        layer: ContextLayer.tools,
        sourceKitId: frame == null
            ? filtered.name
            : (kitIdOf(frame) ?? filtered.name),
        sourceId: filtered.name,
        reason: filtered.reason,
      ),
    );
  }

  exclusions.addAll(_unusedSources(document, llmBodyId));

  return ContextAssembly(
    taskInput: taskInput.trim(),
    instructionText: llmContextText(document, llmBodyId),
    history: trimmed.turns,
    tools: tools,
    items: items,
    exclusions: exclusions,
    omittedHistoryTurns: trimmed.omitted,
  );
}

ContextProvenance _provenanceFor(String kitId, {required bool instruction}) {
  return switch (kitId) {
    boardTextKitId => instruction
        ? ContextProvenance.boardInstruction
        : ContextProvenance.userTask,
    codingCheckResultKitId => ContextProvenance.toolOutput,
    harnessLlmKitId => ContextProvenance.modelOutput,
    _ => ContextProvenance.boardInstruction,
  };
}

({List<ConversationTurn> turns, int omitted}) _trimHistory(
  List<ConversationTurn> turns,
) {
  var used = 0;
  final kept = <ConversationTurn>[];
  for (final turn in turns.reversed) {
    final size = turn.content.length;
    if (kept.isNotEmpty && used + size > contextHistoryCharBudget) {
      break;
    }
    used += size;
    kept.add(turn);
  }
  return (turns: kept.reversed.toList(), omitted: turns.length - kept.length);
}

List<ContextExcerpt> _trimExcerpts(List<ContextExcerpt> excerpts) {
  var used = 0;
  final kept = <ContextExcerpt>[];
  for (final excerpt in excerpts.reversed) {
    final size = excerpt.text.length;
    if (kept.isNotEmpty && used + size > contextExcerptCharBudget) {
      break;
    }
    used += size;
    kept.add(excerpt);
  }
  return kept.reversed.toList();
}

List<ContextExclusion> _compactionNotes(
  SceneDocument document,
  String llmBodyId,
) {
  final notes = <ContextExclusion>[];
  for (final frame in conversationFrames(document)) {
    if (!kitHasLink(frame, to: llmBodyId, port: llmConversationPort)) {
      continue;
    }
    final body = conversationBody(document, frame);
    if (body == null) {
      continue;
    }
    final compaction = conversationCompactionOf(body);
    if (compaction == null || compaction.isEmpty) {
      continue;
    }
    notes.add(
      ContextExclusion(
        layer: ContextLayer.history,
        sourceKitId: harnessConversationKitId,
        sourceId: frame.id,
        reason:
            'Turns ${compaction.fromTurn + 1}-${compaction.toTurn} condensed; '
            'originals remain in the Conversation kit',
      ),
    );
  }
  return notes;
}

List<ContextExclusion> _unusedSources(
  SceneDocument document,
  String llmBodyId,
) {
  final body = document.objectById(llmBodyId);
  final exclusions = <ContextExclusion>[];
  for (final frame in conversationFrames(document)) {
    if (!kitHasLink(frame, to: llmBodyId, port: llmConversationPort)) {
      exclusions.add(
        ContextExclusion(
          layer: ContextLayer.history,
          sourceKitId: harnessConversationKitId,
          sourceId: frame.id,
          reason: 'Not cabled to Conversation',
        ),
      );
    }
  }
  for (final frame in document.objects) {
    if (frame.props[skapieRoleProp] != 'frame' ||
        kitIdOf(frame) != codingCheckResultKitId ||
        kitHasLink(frame, to: llmBodyId, port: llmContextPort)) {
      continue;
    }
    exclusions.add(
      ContextExclusion(
        layer: ContextLayer.instructions,
        sourceKitId: codingCheckResultKitId,
        sourceId: frame.id,
        reason: 'Not cabled to Context',
      ),
    );
  }
  for (final frame in textFrames(document)) {
    final asInput = kitHasLink(frame, to: llmBodyId, port: llmInputPort);
    final asContext = kitHasLink(frame, to: llmBodyId, port: llmContextPort);
    final asOutput =
        body != null && kitHasLink(body, to: frame.id, port: llmTextOutPort);
    if (asInput || asContext || asOutput) {
      continue;
    }
    exclusions.add(
      ContextExclusion(
        layer: ContextLayer.task,
        sourceKitId: boardTextKitId,
        sourceId: frame.id,
        reason: 'Not cabled to Input or Context',
      ),
    );
  }
  for (final frame in repositoryFrames(document)) {
    exclusions.add(
      ContextExclusion(
        layer: ContextLayer.excerpts,
        sourceKitId: codingRepositoryKitId,
        sourceId: frame.id,
        reason: 'Repository root only; no file text is sent unless a read tool runs',
      ),
    );
  }
  return exclusions;
}

/// Build a preview excerpt from one `repo_read_file` result, or null.
ContextExcerpt? contextExcerptFromRead({
  required String callId,
  required String toolName,
  required Map<String, Object?> result,
  String? sourceKitId,
}) {
  if (toolName != 'repo_read_file' || result['ok'] == false) {
    return null;
  }
  final path = result['path']?.toString() ?? '';
  final content = result['content']?.toString() ?? '';
  if (path.isEmpty || content.isEmpty) {
    return null;
  }
  return ContextExcerpt(
    toolName: toolName,
    sourceKitId: sourceKitId ?? toolName,
    sourceId: callId,
    text: content,
    path: path,
    lineStart: (result['startLine'] as num?)?.toInt(),
    lineEnd: (result['endLine'] as num?)?.toInt(),
    truncated: result['truncated'] == true,
  );
}

/// Compact facts for the run ledger: what went in and what was left out.
Map<String, Object?> contextProvenancePayload(ContextAssembly assembly) => {
  'included': assembly.items.length,
  'excluded': assembly.exclusions.length,
  'truncated': assembly.isTruncated,
  'contextChars': assembly.totalChars,
  'omittedHistoryTurns': assembly.omittedHistoryTurns,
  'sources': [
    for (final item in assembly.items)
      '${item.provenance.name}:${item.layer.name}:${item.sourceRange}',
  ],
  'exclusions': [
    for (final exclusion in assembly.exclusions)
      '${exclusion.sourceKitId}:${exclusion.reason}',
  ],
};

/// Provenance for one model request, read from the live message list.
/// The tool loop rebuilds later requests this way, so each turn is recorded.
Map<String, Object?> contextProvenanceForMessages(
  List<AgentMessage> messages, {
  List<AgentTool> tools = const [],
}) {
  final sources = <String>[];
  for (final message in messages) {
    final provenance = switch (message.role) {
      AgentRole.system => ContextProvenance.boardInstruction,
      AgentRole.user => ContextProvenance.userTask,
      AgentRole.assistant => ContextProvenance.modelOutput,
      AgentRole.tool => ContextProvenance.toolOutput,
    };
    sources.add(
      '${provenance.name}:${message.role.name}:${message.content.length}',
    );
  }
  return {
    'included': messages.length + tools.length,
    'excluded': 0,
    'truncated': false,
    'sources': sources,
    'tools': [for (final tool in tools) tool.name],
  };
}

String _sourceRange(String kitLabel, String? path, int? start, int? end) {
  if (path == null || path.isEmpty) {
    return kitLabel;
  }
  final lines = start == null
      ? ''
      : end == null || end == start
      ? ':$start'
      : ':$start-$end';
  return '$path$lines';
}

String _boundedBody(String text, {int max = 200}) {
  final flat = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (flat.isEmpty) {
    return '';
  }
  return flat.length <= max ? flat : '${flat.substring(0, max)}...';
}

/// Readable multi-line summary. Used by the full-screen preview and tests.
String formatContextAssembly(ContextAssembly assembly) {
  final buffer = StringBuffer('Context assembly');
  for (final layer in ContextLayer.values) {
    final items = assembly.itemsFor(layer);
    if (items.isEmpty) {
      continue;
    }
    buffer.write('\n\n${layer.label}');
    for (final item in items) {
      buffer.write(
        '\n${item.order}. ${item.sourceRange}'
        ' · ${item.provenance.label}'
        '${item.truncated ? ' · Truncated' : ''}'
        '\n   ${item.reason}',
      );
      final body = _boundedBody(item.text);
      if (body.isNotEmpty) {
        buffer.write('\n   $body');
      }
    }
  }
  if (assembly.exclusions.isEmpty) {
    return buffer.toString();
  }
  buffer.write('\n\nExcluded');
  for (final exclusion in assembly.exclusions) {
    buffer.write('\n${exclusion.sourceKitId} · ${exclusion.reason}');
  }
  return buffer.toString();
}
