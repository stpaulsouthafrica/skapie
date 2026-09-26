import 'dart:convert';
import 'dart:io';

import 'package:skapie/agent/run_control.dart';
import 'package:skapie/kit_api/kit_api.dart';
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
      schemaVersion:
          migrated['schemaVersion'] as int? ?? runCheckpointSchemaVersion,
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
      at:
          DateTime.tryParse(migrated['at']?.toString() ?? '')?.toUtc() ??
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
    required this.kind,
    required this.uncertain,
    required this.resumable,
  });

  final String runId;
  final String bodyId;

  /// `agent` or `check`.
  final String kind;

  /// An effect started and its result was never seen.
  final bool uncertain;

  /// A checkpoint exists, so Continue can carry the counters forward.
  final bool resumable;

  bool get canContinue => kind == 'agent' && resumable && !uncertain;
}

/// Digest of the board shape: kit identity, cables, and the props that grant or
/// route work. Reply text, coordinates, and last-use stamps stay out, so a
/// resume is not flagged changed by ordinary activity.
String graphRevision(SceneDocument document) {
  final buffer = StringBuffer();
  for (final object in document.objects) {
    buffer
      ..write(object.id)
      ..write('|')
      ..write(object.type)
      ..write('|')
      ..write(object.props[skapieKitProp] ?? '')
      ..write('|')
      ..write(object.props[skapieRoleProp] ?? '')
      ..write('|');
    final links = object.props[linksProp];
    if (links is List) {
      for (final link in links) {
        if (link is Map) {
          buffer.write('${link['to']}:${link['port']},');
        }
      }
    }
    for (final key in const [
      'toolName',
      'requiresRepository',
      'repositoryPath',
      writeScopePathProp,
      'checkPreset',
    ]) {
      final value = object.props[key];
      if (value != null) buffer.write('$key=$value;');
    }
    buffer.write('\n');
  }
  return fnv1aHex(buffer.toString());
}

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
  final Set<String> _dismissed = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final target = file;
    if (target == null || !await target.exists()) {
      return;
    }
    String text;
    try {
      text = await target.readAsString();
    } on FileSystemException {
      return;
    }
    if (text.trim().isEmpty) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is Map) {
      replaceFromJson(Map<String, Object?>.from(decoded));
    }
  }

  List<RunCheckpoint> get checkpoints => List.unmodifiable(_byRun.values);

  RunCheckpoint? forRun(String runId) => _byRun[runId];

  /// True when the user already chose End for this run.
  bool isDismissed(String runId) => _dismissed.contains(runId);

  Future<void> dismiss(String runId) async {
    await load();
    _dismissed.add(runId);
    await _persist();
  }

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
    while (_dismissed.length > runCheckpointKeep * 2) {
      _dismissed.remove(_dismissed.first);
    }
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
    if (_dismissed.isNotEmpty) 'dismissed': _dismissed.toList(),
  };

  void replaceFromJson(Map<String, Object?> json) {
    _byRun.clear();
    _dismissed.clear();
    final raw = json['checkpoints'];
    if (raw is Map) {
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
    final rawDismissed = json['dismissed'];
    if (rawDismissed is List) {
      for (final item in rawDismissed) {
        _dismissed.add('$item');
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
