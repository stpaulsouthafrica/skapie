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
      modelTurns == 0 ? 0 : modelTurns + (extraTurnAfterFailedCheck ? 1 : 0);

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

/// Every run uses the same visible limits.
RunLimits runLimitsFor(SceneDocument document, String llmBodyId) {
  return const RunLimits();
}
