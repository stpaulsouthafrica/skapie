import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

const defaultRunModelTurns = 8;
const defaultRunToolCalls = 16;
const defaultRunSeconds = 120;
const defaultRunOutputChars = 32000;

enum RunPhase {
  ready,
  validating,
  assembling,
  modelWait,
  toolWait,
  paused,
  cancelling,
  completed,
  failed,
  interrupted,
}

bool runPhaseCanMove(RunPhase from, RunPhase to) {
  if (from == to) return true;
  return switch (from) {
    RunPhase.ready => to == RunPhase.validating || to == RunPhase.cancelling,
    RunPhase.validating =>
      to == RunPhase.assembling ||
          to == RunPhase.failed ||
          to == RunPhase.cancelling,
    RunPhase.assembling =>
      to == RunPhase.modelWait ||
          to == RunPhase.failed ||
          to == RunPhase.cancelling,
    RunPhase.modelWait =>
      to == RunPhase.toolWait ||
          to == RunPhase.completed ||
          to == RunPhase.failed ||
          to == RunPhase.cancelling,
    RunPhase.toolWait =>
      to == RunPhase.modelWait ||
          to == RunPhase.failed ||
          to == RunPhase.cancelling,
    RunPhase.cancelling => to == RunPhase.paused || to == RunPhase.interrupted,
    RunPhase.paused ||
    RunPhase.completed ||
    RunPhase.failed ||
    RunPhase.interrupted => false,
  };
}

class RunLimits {
  const RunLimits({
    this.modelTurns = defaultRunModelTurns,
    this.toolCalls = defaultRunToolCalls,
    this.elapsed = const Duration(seconds: defaultRunSeconds),
    this.outputChars = defaultRunOutputChars,
    this.extraTurnAfterFailedCheck = false,
  });

  final int modelTurns;
  final int toolCalls;
  final Duration elapsed;
  final int outputChars;
  final bool extraTurnAfterFailedCheck;

  int get effectiveModelTurns =>
      modelTurns + (extraTurnAfterFailedCheck ? 1 : 0);

  Map<String, Object?> toJson() => {
    'modelTurns': modelTurns,
    'toolCalls': toolCalls,
    'elapsedSeconds': elapsed.inSeconds,
    'outputChars': outputChars,
    'extraTurnAfterFailedCheck': extraTurnAfterFailedCheck,
  };
}

class RunLimitReached implements Exception {
  const RunLimitReached(this.name);
  final String name;

  @override
  String toString() => '$name limit reached';
}

int _bounded(Object? value, int fallback, int maximum) {
  final parsed = value is int ? value : int.tryParse('$value');
  return parsed == null ? fallback : parsed.clamp(1, maximum);
}

/// A Run Control affects only the LLM it is cabled to. Existing boards use
/// the visible defaults until one is connected.
RunLimits runLimitsFor(SceneDocument document, String llmBodyId) {
  final frames = [
    for (final object in document.objects)
      if (kitIdOf(object) == harnessRunControlKitId &&
          object.props[skapieRoleProp] == 'frame' &&
          kitHasLink(object, to: llmBodyId, port: runControlPort))
        object,
  ];
  if (frames.length != 1) {
    return const RunLimits();
  }
  final frame = frames.single;
  final failedCheckConnected = document.objects.any(
    (object) =>
        kitIdOf(object) == codingCheckResultKitId &&
        object.props[skapieRoleProp] == 'frame' &&
        kitHasLink(object, to: frame.id, port: runCheckFeedbackPort) &&
        (kitMembers(document: document, selectedId: object.id) ?? const []).any(
          (member) => member.props['checkOutcome'] == 'nonzero_exit',
        ),
  );
  return RunLimits(
    modelTurns: _bounded(frame.props['modelTurns'], defaultRunModelTurns, 100),
    toolCalls: _bounded(frame.props['toolCalls'], defaultRunToolCalls, 500),
    elapsed: Duration(
      seconds: _bounded(frame.props['elapsedSeconds'], defaultRunSeconds, 3600),
    ),
    outputChars: _bounded(
      frame.props['outputChars'],
      defaultRunOutputChars,
      1000000,
    ),
    extraTurnAfterFailedCheck:
        frame.props['failedCheckRule'] == 'oneMoreTurn' && failedCheckConnected,
  );
}
