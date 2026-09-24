import 'dart:convert';
import 'dart:io';

/// Schema for [RunRecord] and [RunEvent]. Bump when the fields change.
const int runRecordSchemaVersion = 1;

/// Longest string stored inside one event. Longer text is cut and marked.
const int runPayloadTextLimit = 280;

/// Events shown at once in the run evidence list.
const int runEvidencePageSize = 12;

/// Stored history at or above this size asks the user to notice. Nothing is deleted.
const int runHistoryWarnBytes = 512 * 1024;

/// Later slices record these. A size limit must not drop them.
const Set<String> protectedRunEvidenceKinds = {
  'proposal',
  'approval',
  'apply',
  'revert',
};

bool runEvidenceMayDrop(String kind) =>
    !protectedRunEvidenceKinds.contains(kind) && false;

/// Events the current reader can emit. Proposal, approval, and command
/// events stay out until those actions exist.
enum RunEventKind {
  runRequested,
  graphValidated,
  modelRequestStarted,
  modelRequestFinished,
  toolCallStarted,
  toolCallFinished,
  runCompleted,
  runFailed,
  runInterrupted,
}

enum RunStatus { running, completed, failed, interrupted }

class RunEvent {
  const RunEvent({
    required this.schemaVersion,
    required this.sequence,
    required this.at,
    required this.kind,
    this.payload = const {},
  });

  final int schemaVersion;
  final int sequence;
  final DateTime at;
  final RunEventKind kind;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'sequence': sequence,
    'at': at.toUtc().toIso8601String(),
    'kind': kind.name,
    'payload': payload,
  };

  static RunEvent fromJson(Map<String, Object?> json) {
    final kindName = json['kind']?.toString() ?? '';
    final kind = RunEventKind.values.where((value) => value.name == kindName);
    if (kind.isEmpty) {
      throw FormatException('Unknown run event kind: $kindName');
    }
    final rawPayload = json['payload'];
    return RunEvent(
      schemaVersion: json['schemaVersion'] as int? ?? runRecordSchemaVersion,
      sequence: json['sequence'] as int? ?? 0,
      at: DateTime.parse(json['at']?.toString() ?? '').toUtc(),
      kind: kind.single,
      payload: rawPayload is Map
          ? Map<String, Object?>.from(rawPayload)
          : const {},
    );
  }
}

class RunRecord {
  RunRecord({
    required this.id,
    required this.bodyId,
    this.schemaVersion = runRecordSchemaVersion,
    List<RunEvent> events = const [],
  }) : events = List.of(events);

  final int schemaVersion;
  final String id;
  final String bodyId;
  final List<RunEvent> events;

  RunStatus get status {
    for (final event in events.reversed) {
      switch (event.kind) {
        case RunEventKind.runCompleted:
          return RunStatus.completed;
        case RunEventKind.runFailed:
          return RunStatus.failed;
        case RunEventKind.runInterrupted:
          return RunStatus.interrupted;
        default:
          continue;
      }
    }
    return RunStatus.running;
  }

  bool get isTerminal => status != RunStatus.running;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'bodyId': bodyId,
    'events': [for (final event in events) event.toJson()],
  };

  static RunRecord fromJson(Map<String, Object?> json) {
    final rawEvents = json['events'];
    return RunRecord(
      schemaVersion: json['schemaVersion'] as int? ?? runRecordSchemaVersion,
      id: json['id']?.toString() ?? '',
      bodyId: json['bodyId']?.toString() ?? '',
      events: [
        if (rawEvents is List)
          for (final item in rawEvents)
            if (item is Map) RunEvent.fromJson(Map<String, Object?>.from(item)),
      ],
    );
  }
}

/// Saved log of executions. Not part of the scene document.
class RunLedger {
  RunLedger({
    DateTime Function()? clock,
    this.onAppend,
    this.historyWarnBytes = runHistoryWarnBytes,
  }) : _clock = clock;

  final DateTime Function()? _clock;
  final void Function()? onAppend;
  final int historyWarnBytes;
  var closedIncomplete = false;
  final List<RunRecord> _runs = [];
  final Map<String, String> _bodies = {};
  var _nextId = 0;

  List<RunRecord> get runs => List.unmodifiable(_runs);

  RunRecord? runById(String id) {
    for (final run in _runs) {
      if (run.id == id) {
        return run;
      }
    }
    return null;
  }

  List<RunRecord> runsFor(String bodyId) => [
    for (final run in _runs)
      if (run.bodyId == bodyId) run,
  ];

  RunRecord begin({required String bodyId}) {
    _nextId++;
    final run = RunRecord(id: 'run_$_nextId', bodyId: bodyId);
    _runs.add(run);
    return run;
  }

  /// Appends one event. Sequence and wall time both increase.
  /// A second terminal event is ignored so an interrupted run stays interrupted.
  RunEvent? append(
    String runId,
    RunEventKind kind, [
    Map<String, Object?> payload = const {},
  ]) {
    final run = runById(runId);
    if (run == null || run.isTerminal) {
      return null;
    }
    final previous = run.events.isEmpty ? null : run.events.last;
    final sequence = (previous?.sequence ?? 0) + 1;
    var at = (_clock ?? DateTime.now)().toUtc();
    final prior = previous?.at;
    if (prior != null && !at.isAfter(prior)) {
      at = prior.add(const Duration(microseconds: 1));
    }
    final formatted = formatRunPayload(payload);
    final event = RunEvent(
      schemaVersion: runRecordSchemaVersion,
      sequence: sequence,
      at: at,
      kind: kind,
      payload: Map<String, Object?>.unmodifiable(boundRunPayload(formatted)),
    );
    run.events.add(event);
    final full = runEventEvidenceDetail(
      RunEvent(
        schemaVersion: event.schemaVersion,
        sequence: event.sequence,
        at: event.at,
        kind: event.kind,
        payload: formatted,
      ),
    );
    if (full != null && full.length > runPayloadTextLimit) {
      _bodies['${run.id}:${event.sequence}'] = full;
    }
    onAppend?.call();
    return event;
  }

  /// Full inspect text when the saved payload was cut.
  String? inspectText(RunRecord run, RunEvent event) {
    return _bodies['${run.id}:${event.sequence}'] ??
        runEventEvidenceDetail(event);
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': runRecordSchemaVersion,
    'runs': [for (final run in _runs) run.toJson()],
    if (_bodies.isNotEmpty) 'bodies': _bodies,
  };

  bool get historyWarning =>
      utf8.encode(jsonEncode(toJson())).length >= historyWarnBytes;

  /// Runs left open by a quit become interrupted. Completed runs stay completed.
  int closeIncompleteRuns() {
    var closed = 0;
    for (final run in List<RunRecord>.of(_runs)) {
      if (run.isTerminal) {
        continue;
      }
      append(run.id, RunEventKind.runInterrupted, {'reason': 'reopened'});
      closed++;
    }
    if (closed > 0) {
      closedIncomplete = true;
    }
    return closed;
  }

  void replaceFromJson(Map<String, Object?> json) {
    _runs.clear();
    _bodies.clear();
    final raw = json['runs'];
    if (raw is! List) {
      return;
    }
    for (final item in raw) {
      if (item is Map) {
        _runs.add(RunRecord.fromJson(Map<String, Object?>.from(item)));
      }
    }
    final rawBodies = json['bodies'];
    if (rawBodies is Map) {
      for (final entry in rawBodies.entries) {
        final text = entry.value;
        if (text is String) {
          _bodies['${entry.key}'] = text;
        }
      }
    }
    _nextId = 0;
    for (final run in _runs) {
      final suffix = int.tryParse(run.id.replaceFirst('run_', ''));
      if (suffix != null && suffix > _nextId) {
        _nextId = suffix;
      }
    }
  }
}

/// Ledger file beside a board. Never written into scene.json.
class RunLedgerFile {
  RunLedgerFile(this.file);

  final File file;

  static RunLedgerFile? besideScene(String? scenePath) {
    if (scenePath == null || scenePath.isEmpty) {
      return null;
    }
    return RunLedgerFile(File('$scenePath.runs.json'));
  }

  Future<void> loadInto(RunLedger ledger) async {
    if (!await file.exists()) {
      return;
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return;
    }
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      ledger.replaceFromJson(Map<String, Object?>.from(decoded));
      ledger.closeIncompleteRuns();
    }
  }

  Future<void> write(RunLedger ledger) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(ledger.toJson())}\n');
  }
}

Map<String, Object?> boundRunPayload(Map<String, Object?> payload) {
  var truncated = payload['truncated'] == true;
  final next = <String, Object?>{};
  for (final entry in payload.entries) {
    final value = entry.value;
    if (value is String && value.length > runPayloadTextLimit) {
      truncated = true;
      next[entry.key] = value.substring(0, runPayloadTextLimit);
    } else {
      next[entry.key] = value;
    }
  }
  if (truncated) {
    next['truncated'] = true;
  }
  return next;
}

class RunEvidencePage {
  const RunEvidencePage({
    required this.events,
    required this.page,
    required this.pageCount,
  });

  final List<RunEvent> events;
  final int page;
  final int pageCount;
}

RunEvidencePage runEvidencePage(RunRecord? run, int page) {
  final events = run?.events ?? const <RunEvent>[];
  if (events.isEmpty) {
    return const RunEvidencePage(events: [], page: 0, pageCount: 1);
  }
  final pageCount = (events.length / runEvidencePageSize).ceil();
  final index = page.clamp(0, pageCount - 1);
  final start = index * runEvidencePageSize;
  final end = (start + runEvidencePageSize).clamp(0, events.length);
  return RunEvidencePage(
    events: events.sublist(start, end),
    page: index,
    pageCount: pageCount,
  );
}

String runEventEvidenceLine(RunEvent event) {
  final mark = event.payload['truncated'] == true ? ' · Truncated' : '';
  return '${event.sequence}. ${runEventLabel(event.kind)}$mark';
}

Map<String, Object?> formatRunPayload(Map<String, Object?> payload) {
  final next = <String, Object?>{};
  for (final entry in payload.entries) {
    final value = entry.value;
    next[entry.key] = value is String ? presentRunInspect(value) : value;
  }
  return next;
}

/// Token counts the server actually sent. Cost is never derived.
Map<String, int>? tokenUsageFromResponse(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) {
    return null;
  }
  final usage = decoded['usage'];
  if (usage is! Map) {
    return null;
  }
  const keys = [
    'prompt_tokens',
    'completion_tokens',
    'total_tokens',
    'input_tokens',
    'output_tokens',
  ];
  final counts = <String, int>{};
  for (final key in keys) {
    final value = usage[key];
    if (value is num) {
      counts[key] = value.toInt();
    }
  }
  return counts.isEmpty ? null : counts;
}

String presentRunInspect(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } on FormatException {
    return raw;
  }
}

/// Text for the Full Screen viewer. A timestamp stands in when the event
/// stored no payload body.
String runEventInspectBody(RunEvent event) {
  return runEventEvidenceDetail(event) ??
      'Recorded at ${event.at.toUtc().toIso8601String()}';
}

/// Facts beside the payload: time, and anything that is not the main body.
String runEventInspectAside(RunEvent event) {
  const bodyKeys = {
    'request',
    'response',
    'text',
    'result',
    'arguments',
    'error',
  };
  final lines = <String>[
    'At: ${event.at.toUtc().toIso8601String()}',
    'Sequence: ${event.sequence}',
    for (final line in runEventDetailLines(event))
      if (!bodyKeys.any((key) => line.startsWith('$key:'))) line,
  ];
  return lines.join('\n');
}

String? runEventEvidenceDetail(RunEvent event) {
  for (final key in [
    'request',
    'response',
    'text',
    'result',
    'arguments',
    'error',
  ]) {
    final value = event.payload[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String runEventSummary(RunEvent event) {
  final name = event.payload['name'];
  final model = event.payload['model'];
  final extra = name is String && name.isNotEmpty
      ? name
      : model is String && model.isNotEmpty
      ? model
      : '';
  final failed =
      event.kind == RunEventKind.runFailed || event.payload['ok'] == false;
  final mark = failed ? ' · Failed' : '';
  final tail = extra.isEmpty ? '' : ' · $extra';
  return '${event.sequence}. ${runEventLabel(event.kind)}$tail$mark';
}

/// Bounded lines for an expanded timeline row. Route ids stay off the card.
List<String> runEventDetailLines(RunEvent event) {
  const hidden = {'kits', 'cables', 'truncated', 'bodyId', 'callId'};
  final lines = <String>[];
  for (final entry in event.payload.entries) {
    if (hidden.contains(entry.key)) {
      continue;
    }
    final text = _detailValue(entry.value);
    if (text.isEmpty) {
      continue;
    }
    lines.add('${entry.key}: $text');
  }
  return lines;
}

String _detailValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is List) {
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .join(', ');
  }
  if (value is Map) {
    return '';
  }
  final text = '$value'.replaceAll('\n', ' ').trim();
  if (text.length <= runPayloadTextLimit) {
    return text;
  }
  return text.substring(0, runPayloadTextLimit);
}

String runEventLabel(RunEventKind kind) => switch (kind) {
  RunEventKind.runRequested => 'Run requested',
  RunEventKind.graphValidated => 'Graph validated',
  RunEventKind.modelRequestStarted => 'Model request started',
  RunEventKind.modelRequestFinished => 'Model request finished',
  RunEventKind.toolCallStarted => 'Tool call started',
  RunEventKind.toolCallFinished => 'Tool call finished',
  RunEventKind.runCompleted => 'Run completed',
  RunEventKind.runFailed => 'Run failed',
  RunEventKind.runInterrupted => 'Run interrupted',
};
