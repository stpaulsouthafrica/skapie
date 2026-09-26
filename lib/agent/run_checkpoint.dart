import 'dart:convert';
import 'dart:io';

import 'package:skapie/agent/run_control.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/shared/text_digest.dart';

/// Schema for [RunCheckpoint]. Bump when a field changes and add a migration.
const int runCheckpointSchemaVersion = 1;

/// Checkpoints kept for one board. Only the latest per run matters; old runs
/// are dropped so the file stays small.
const int runCheckpointKeep = 50;

/// A stable observed boundary. A checkpoint is written only after one.
enum RunBoundary {
  started,
  graphValidated,
  modelResult,
  toolResult,
  approvalDecision,
  patchResult,
  checkResult,
}

/// A small save point for one run. It does not copy the context or the scene.
class RunCheckpoint {
  const RunCheckpoint({
    required this.runId,
    required this.bodyId,
    required this.phase,
    required this.boundary,
    required this.modelTurns,
    required this.toolCalls,
    required this.outputChars,
    required this.graphRevision,
    this.pendingOperationId,
    this.resumedFrom,
    required this.at,
    this.schemaVersion = runCheckpointSchemaVersion,
  });

  final int schemaVersion;
  final String runId;
  final String bodyId;
  final String phase;
  final RunBoundary boundary;
  final int modelTurns;
  final int toolCalls;
  final int outputChars;
  final String graphRevision;

  /// An effect started but not yet observed, if any.
  final String? pendingOperationId;

  /// The run this one continues, after a resume.
  final String? resumedFrom;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'runId': runId,
    'bodyId': bodyId,
    'phase': phase,
    'boundary': boundary.name,
    'modelTurns': modelTurns,
    'toolCalls': toolCalls,
    'outputChars': outputChars,
    'graphRevision': graphRevision,
    if (pendingOperationId != null) 'pendingOperationId': pendingOperationId,
    if (resumedFrom != null) 'resumedFrom': resumedFrom,
    'at': at.toUtc().toIso8601String(),
  };

  static RunCheckpoint fromJson(Map<String, Object?> json) {
    final migrated = migrateRunCheckpoint(json);
    final boundaryName = migrated['boundary']?.toString() ?? '';
    final boundary = RunBoundary.values.firstWhere(
      (value) => value.name == boundaryName,
      orElse: () => RunBoundary.started,
    );
    return RunCheckpoint(
      schemaVersion: migrated['schemaVersion'] as int? ??
          runCheckpointSchemaVersion,
      runId: migrated['runId']?.toString() ?? '',
      bodyId: migrated['bodyId']?.toString() ?? '',
      phase: migrated['phase']?.toString() ?? RunPhase.ready.name,
      boundary: boundary,
      modelTurns: migrated['modelTurns'] as int? ?? 0,
      toolCalls: migrated['toolCalls'] as int? ?? 0,
      outputChars: migrated['outputChars'] as int? ?? 0,
      graphRevision: migrated['graphRevision']?.toString() ?? '',
      pendingOperationId: migrated['pendingOperationId']?.toString(),
      resumedFrom: migrated['resumedFrom']?.toString(),
      at: DateTime.tryParse(migrated['at']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

/// Migration path for a saved checkpoint. Older files are lifted, never
/// discarded. Version 0 is the first shape; it needs no field changes yet.
Map<String, Object?> migrateRunCheckpoint(Map<String, Object?> json) {
  final version = json['schemaVersion'] as int? ?? 0;
  if (version >= runCheckpointSchemaVersion) {
    return json;
  }
  return {...json, 'schemaVersion': runCheckpointSchemaVersion};
}

/// One run left unfinished by a quit, for the recovery banner.
class RecoveryNotice {
  const RecoveryNotice({
    required this.runId,
    required this.bodyId,
    required this.uncertain,
    required this.resumable,
  });

  final String runId;
  final String bodyId;

  /// An effect started and its result was never seen.
  final bool uncertain;

  /// A checkpoint exists, so Continue can carry the counters forward.
  final bool resumable;
}

/// Digest of the board objects and cables. A resume can tell if the graph moved.
String graphRevision(SceneDocument document) =>
    fnv1aHex(jsonEncode(document.toJson()));

/// Saved checkpoints beside a board. Never written into scene.json.
class RunCheckpointStore {
  RunCheckpointStore({this.file});

  factory RunCheckpointStore.besideScene(String? scenePath) =>
      RunCheckpointStore(
        file: scenePath == null || scenePath.isEmpty
            ? null
            : File('$scenePath.checkpoints.json'),
      );

  final File? file;
  final Map<String, RunCheckpoint> _byRun = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final target = file;
    if (target == null || !await target.exists()) {
      return;
    }
    final text = await target.readAsString();
    if (text.trim().isEmpty) {
      return;
    }
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      replaceFromJson(Map<String, Object?>.from(decoded));
    }
  }

  List<RunCheckpoint> get checkpoints => List.unmodifiable(_byRun.values);

  RunCheckpoint? forRun(String runId) => _byRun[runId];

  RunCheckpoint? latestFor(String bodyId) {
    RunCheckpoint? latest;
    for (final checkpoint in _byRun.values) {
      if (checkpoint.bodyId != bodyId) continue;
      if (latest == null || checkpoint.at.isAfter(latest.at)) {
        latest = checkpoint;
      }
    }
    return latest;
  }

  Future<void> save(RunCheckpoint checkpoint) async {
    await load();
    _byRun[checkpoint.runId] = checkpoint;
    _trim();
    await _persist();
  }

  Future<void> remove(String runId) async {
    await load();
    if (_byRun.remove(runId) == null) return;
    await _persist();
  }

  void _trim() {
    if (_byRun.length <= runCheckpointKeep) return;
    final ordered = _byRun.values.toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    for (final checkpoint in ordered.take(_byRun.length - runCheckpointKeep)) {
      _byRun.remove(checkpoint.runId);
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': runCheckpointSchemaVersion,
    'checkpoints': {
      for (final entry in _byRun.entries) entry.key: entry.value.toJson(),
    },
  };

  void replaceFromJson(Map<String, Object?> json) {
    _byRun.clear();
    final raw = json['checkpoints'];
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is Map) {
        final checkpoint = RunCheckpoint.fromJson(
          Map<String, Object?>.from(value),
        );
        _byRun[checkpoint.runId] = checkpoint;
      }
    }
  }

  Future<void> _persist() async {
    final target = file;
    if (target == null) return;
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
      flush: true,
    );
    await temp.rename(target.path);
  }
}
