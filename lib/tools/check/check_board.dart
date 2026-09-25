import 'dart:io';

import 'package:flutter/services.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/check/check_redaction.dart';

const gitDiffCheckPreset = 'git-diff-check';

const Map<String, Object?> checkSpecKitJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': codingCheckSpecKitId,
  'displayName': 'Check Spec',
  'description': 'Choose one trusted check. No shell text is accepted.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': textFrameHeight,
      'props': {
        skapieKitProp: codingCheckSpecKitId,
        skapieRoleProp: 'frame',
        checkPresetProp: '',
      },
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 40,
      'width': 256,
      'height': 48,
      'props': {
        skapieKitProp: codingCheckSpecKitId,
        skapieRoleProp: 'body',
        'content': 'Choose a check in Inspector',
        'fontSize': 13,
      },
    },
  ],
};

const Map<String, Object?> runCheckKitJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': codingRunCheckKitId,
  'displayName': 'Run Check',
  'description':
      'An explicit execution effect requiring a separate Write Scope.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': textFrameHeight,
      'props': {skapieKitProp: codingRunCheckKitId, skapieRoleProp: 'frame'},
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 40,
      'width': 256,
      'height': 48,
      'props': {
        skapieKitProp: codingRunCheckKitId,
        skapieRoleProp: 'body',
        'content': 'Connect Spec, Write Scope, and Result',
        'fontSize': 13,
      },
    },
  ],
};

const Map<String, Object?> checkResultKitJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': codingCheckResultKitId,
  'displayName': 'Check Result',
  'description':
      'The latest check outcome; a user may cable it to LLM Context.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': textFrameHeight,
      'props': {skapieKitProp: codingCheckResultKitId, skapieRoleProp: 'frame'},
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 40,
      'width': 256,
      'height': 48,
      'props': {
        skapieKitProp: codingCheckResultKitId,
        skapieRoleProp: 'body',
        'content': 'No check run yet',
        'fontSize': 13,
        'checkOutcome': '',
      },
    },
  ],
};

KitRecipe _recipe(Map<String, Object?> json) =>
    parseKitPackageJson(json, folderId: json['id']!.toString()).recipe;

void registerCheckKits(KitApi kitApi) {
  kitApi.registerKit(_recipe(checkSpecKitJson));
  kitApi.registerKit(_recipe(runCheckKitJson));
  kitApi.registerKit(_recipe(checkResultKitJson));
}

abstract class CheckProcessRunner {
  Future<Map<String, Object?>> runGitDiffCheck(
    String root, {
    void Function(CheckProcessChunk)? onChunk,
  });
  Future<bool> cancel();
}

class CheckProcessChunk {
  const CheckProcessChunk({
    required this.phase,
    required this.stream,
    required this.text,
    required this.at,
  });
  final String phase;
  final String stream;
  final String text;
  final String at;
}

class SystemCheckProcessRunner implements CheckProcessRunner {
  const SystemCheckProcessRunner();
  static const _channel = MethodChannel('skapie/checks');

  @override
  Future<Map<String, Object?>> runGitDiffCheck(
    String root, {
    void Function(CheckProcessChunk)? onChunk,
  }) async {
    if (!Platform.isMacOS) {
      return {
        'outcome': 'infrastructure_error',
        'error': 'Checks require macOS.',
      };
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'checkChunk' || onChunk == null) return;
      final data = Map<String, Object?>.from(call.arguments as Map);
      onChunk(
        CheckProcessChunk(
          phase: data['phase']?.toString() ?? 'check',
          stream: data['stream']?.toString() ?? 'stdout',
          text: data['text']?.toString() ?? '',
          at: data['at']?.toString() ?? '',
        ),
      );
    });
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'runGitDiffCheck',
        {'root': root},
      );
      return raw ??
          {'outcome': 'infrastructure_error', 'error': 'No native result.'};
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  @override
  Future<bool> cancel() async =>
      Platform.isMacOS &&
      (await _channel.invokeMethod<bool>('cancelGitDiffCheck') ?? false);
}

SceneObject? _body(SceneDocument document, SceneObject frame) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] == 'body' &&
        kitIdOf(object) == kitIdOf(frame) &&
        kitChildBelongsToFrame(object, frame)) {
      return object;
    }
  }
  return null;
}

SceneObject? _linkedFrame(
  SceneDocument document,
  String targetId,
  String port,
  String kitId,
) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] == 'frame' &&
        kitIdOf(object) == kitId &&
        kitHasLink(object, to: targetId, port: port)) {
      return object;
    }
  }
  return null;
}

SceneObject? connectedCheckSpec(SceneDocument document, String runFrameId) =>
    _linkedFrame(document, runFrameId, checkSpecPort, codingCheckSpecKitId);

SceneObject? connectedCheckWriteScope(
  SceneDocument document,
  String runFrameId,
) => _linkedFrame(document, runFrameId, checkWritePort, codingWriteScopeKitId);

SceneObject? connectedCheckResult(SceneDocument document, String runFrameId) {
  final run = document.objectById(runFrameId);
  if (run == null) return null;
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] == 'frame' &&
        kitIdOf(object) == codingCheckResultKitId &&
        kitHasLink(run, to: object.id, port: checkResultPort)) {
      return object;
    }
  }
  return null;
}

SceneObject? checkResultBody(SceneDocument document, String resultFrameId) {
  final frame = document.objectById(resultFrameId);
  return frame == null ? null : _body(document, frame);
}

class CheckGate {
  const CheckGate(this.reason);
  final String reason;
  bool get ready => reason.isEmpty;
}

CheckGate checkGate(SceneDocument document, String runFrameId) {
  final frame = document.objectById(runFrameId);
  if (frame == null || kitIdOf(frame) != codingRunCheckKitId) {
    return const CheckGate('Run Check kit is missing.');
  }
  final spec = connectedCheckSpec(document, runFrameId);
  if (spec == null) return const CheckGate('Connect Check Spec to Run Check.');
  if (spec.props[checkPresetProp] != gitDiffCheckPreset) {
    return const CheckGate('Choose the trusted Git diff check in Check Spec.');
  }
  final scope = connectedCheckWriteScope(document, runFrameId);
  if (scope == null ||
      (scope.props[writeScopePathProp]?.toString().trim() ?? '').isEmpty) {
    return const CheckGate('Connect a selected Write Scope to Run Check.');
  }
  if (connectedCheckResult(document, runFrameId) == null) {
    return const CheckGate('Connect Run Check to Check Result.');
  }
  return const CheckGate('');
}

class CheckAttempt {
  const CheckAttempt({
    required this.started,
    required this.outcome,
    required this.message,
  });
  final bool started;
  final String outcome;
  final String message;
}

/// Called only from the explicit Run button. Cables are configuration, never a
/// trigger. The native host repeats the live bookmark check before spawning.
Future<CheckAttempt> invokeRunCheck({
  required KitApi kitApi,
  required String runFrameId,
  PatchWritePermission permission = const SystemPatchWritePermission(),
  CheckProcessRunner runner = const SystemCheckProcessRunner(),
  RunRecord Function(String resultBodyId, Map<String, Object?> details)?
  beginEvidence,
  void Function(String runId, RunEventKind kind, Map<String, Object?> payload)?
  appendEvidence,
}) async {
  final document = kitApi.store.document;
  final gate = checkGate(document, runFrameId);
  if (!gate.ready) {
    return CheckAttempt(started: false, outcome: '', message: gate.reason);
  }
  final scope = connectedCheckWriteScope(document, runFrameId)!;
  final root = scope.props[writeScopePathProp]!.toString();
  final result = connectedCheckResult(document, runFrameId)!;
  final body = checkResultBody(document, result.id)!;
  try {
    if (!await permission.canWrite(root) || !await Directory(root).exists()) {
      return const CheckAttempt(
        started: false,
        outcome: '',
        message: 'The live Write Scope is unavailable.',
      );
    }
  } catch (error) {
    return CheckAttempt(
      started: false,
      outcome: '',
      message: 'Write Scope check failed: $error',
    );
  }
  kitApi.updateProps(body.id, {
    'content': 'Running Git diff --check…',
    'checkOutcome': 'running',
  });
  final evidence = beginEvidence?.call(body.id, {
    'preset': gitDiffCheckPreset,
    'cwd': redactCheckText(root),
    'requestedAt': DateTime.now().toUtc().toIso8601String(),
  });
  final lineRedactor = CheckLineRedactor();
  final seen = <String>{};
  void recordChunk(String phase, String stream, String text, String at) {
    if (evidence == null || appendEvidence == null) return;
    final key = '$phase:$stream';
    seen.add(key);
    var batch = '';
    void emit() {
      if (batch.isEmpty) return;
      appendEvidence(evidence.id, RunEventKind.checkOutput, {
        'phase': phase,
        'stream': stream,
        'at': redactCheckText(at),
        'text': batch,
      });
      batch = '';
    }

    for (final line in lineRedactor.add(key, text)) {
      if (batch.isNotEmpty && batch.length + line.length > 2048) emit();
      batch += line;
    }
    emit();
  }

  Map<String, Object?> raw;
  try {
    raw = await runner.runGitDiffCheck(
      root,
      onChunk: (chunk) {
        recordChunk(chunk.phase, chunk.stream, chunk.text, chunk.at);
      },
    );
  } catch (error) {
    raw = {'outcome': 'infrastructure_error', 'error': '$error'};
  }
  if (evidence != null && appendEvidence != null) {
    // Old/native-error paths may return only a final bounded response.
    for (final stream in ['stdout', 'stderr']) {
      if (!seen.contains('check:$stream')) {
        recordChunk('check', stream, raw[stream]?.toString() ?? '', '');
      }
    }
    for (final (key, text) in lineRedactor.finish()) {
      final parts = key.split(':');
      appendEvidence(evidence.id, RunEventKind.checkOutput, {
        'phase': parts.first,
        'stream': parts.last,
        'text': text,
      });
    }
  }
  const categories = {
    'exit_0',
    'nonzero_exit',
    'timeout',
    'cancelled',
    'infrastructure_error',
  };
  final reported = raw['outcome']?.toString() ?? '';
  final outcome = categories.contains(reported)
      ? reported
      : 'infrastructure_error';
  final rawBefore = raw['beforeGit']?.toString() ?? '';
  final rawAfter = raw['afterGit']?.toString() ?? '';
  final before = redactCheckText(rawBefore);
  final after = redactCheckText(rawAfter);
  final known = raw['gitStateKnown'] == true;
  final gitState = known
      ? rawBefore == rawAfter
            ? 'Git status unchanged'
            : 'Git status changed during check'
      : 'Final Git status unavailable';
  final label = switch (outcome) {
    'exit_0' => 'Exited 0',
    'nonzero_exit' => 'Nonzero exit',
    'timeout' => 'Timed out',
    'cancelled' => 'Cancelled',
    _ => 'Infrastructure error',
  };
  final summary = 'Git diff --check · $label · $gitState';
  if (evidence != null && appendEvidence != null) {
    appendEvidence(evidence.id, RunEventKind.checkFinished, {
      'outcome': outcome,
      'argv': [
        for (final part
            in raw['argv'] is List
                ? raw['argv'] as List
                : const ['git', 'diff', '--check'])
          redactCheckText('$part'),
      ],
      'cwd': redactCheckText(raw['cwd']?.toString() ?? root),
      'environmentKeys': raw['environmentKeys'] is List
          ? [
              for (final key in raw['environmentKeys'] as List)
                redactCheckText('$key'),
            ]
          : const <String>[],
      'startedAt': raw['startedAt']?.toString() ?? '',
      'finishedAt':
          raw['finishedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'exitCode': raw['exitCode'],
      'truncated': raw['truncated'] == true,
      'cancelled': outcome == 'cancelled',
      'stopUncertain': raw['stopUncertain'] == true,
      'network': 'allowed_by_app_sandbox',
      'beforeGit': before,
      'afterGit': after,
      'gitStateKnown': known,
      'gitState': gitState,
      'error': redactCheckText(raw['error']?.toString() ?? ''),
    });
  }
  // Only this short summary can flow through the optional LLM Context cable.
  kitApi.updateProps(body.id, {
    'content': summary,
    'checkOutcome': outcome,
    'checkCommand': 'git diff --check',
    'checkNetwork': 'Allowed by app sandbox',
    'checkCwd': redactCheckText(root),
    'checkExitCode': raw['exitCode'],
    'checkStartedAt': raw['startedAt'],
    'checkFinishedAt': raw['finishedAt'],
    'checkBeforeGit': before,
    'checkAfterGit': after,
    'checkGitChanged': known && rawBefore != rawAfter,
    'checkGitStateKnown': known,
    'checkTruncated': raw['truncated'] == true,
    'checkStopUncertain': raw['stopUncertain'] == true,
    'checkError': redactCheckText(raw['error']?.toString() ?? ''),
  });
  return CheckAttempt(started: true, outcome: outcome, message: summary);
}
