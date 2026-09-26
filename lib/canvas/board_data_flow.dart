import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/check/check_board.dart';
import 'package:skapie/tools/patch/patch_board.dart';

/// A route that was actually used by a board value or an explicit effect.
/// Cable ids are ordered from the source to the receiver.
class BoardDataRoute {
  const BoardDataRoute(
    this.cableIds,
    this.frameIds, {
    this.how = 'Value delivered',
  });

  final List<String> cableIds;
  final List<String> frameIds;
  final String how;
}

class BoardCableUse {
  const BoardCableUse(this.at, this.how);

  final DateTime at;
  final String how;
}

class BoardDataEvent {
  const BoardDataEvent(this.sequence, this.route);

  final int sequence;
  final BoardDataRoute route;
}

/// Read only the durable values that the coding kits exchange. Layout edits,
/// connection changes, and transient inspector rebuilds cannot create pulses.
List<BoardDataRoute> boardDataRoutesForChange(
  SceneDocument before,
  SceneDocument after,
) {
  final cables = sceneCables(after);
  final routes = <BoardDataRoute>[];
  for (final frame in after.objects) {
    if (frame.props[skapieRoleProp] != 'frame') continue;
    switch (kitIdOf(frame)) {
      case codingPatchProposalKitId:
        final body = patchProposalBody(after, frame.id);
        final prior = patchProposalBody(before, frame.id);
        if (!validPatchProposal(body) ||
            body!.props[proposalIdProp] == prior?.props[proposalIdProp] &&
                body.props[proposalFingerprintProp] ==
                    prior?.props[proposalFingerprintProp]) {
          break;
        }
        final inputs = _to(cables, frame.id, KitPortKind.proposalIn);
        final outputs = _from(cables, frame.id, KitPortKind.proposalOut);
        for (final input in inputs) {
          if (outputs.isEmpty) {
            routes.add(_route([input], 'Patch proposal delivered'));
          } else {
            for (final output in outputs) {
              routes.add(_route([input, output], 'Patch proposal delivered'));
            }
          }
        }
        if (inputs.isEmpty) {
          for (final output in outputs) {
            routes.add(_route([output], 'Patch proposal delivered'));
          }
        }
      case codingReviewDecisionKitId:
        final body = reviewDecisionBody(after, frame.id);
        final prior = reviewDecisionBody(before, frame.id);
        if (body == null ||
            body.props['reviewedAt'] == prior?.props['reviewedAt'] ||
            (body.props['reviewedAt']?.toString().isEmpty ?? true)) {
          break;
        }
        if (reviewDecisionOf(after, frame.id) == 'accept') {
          for (final cable in _from(cables, frame.id, KitPortKind.reviewOut)) {
            if (!applyPatchGate(after, cable.targetFrameId).inert) {
              routes.add(_route([cable], 'Accepted decision recorded'));
            }
          }
        } else {
          // Rejection is recorded on Review; nothing goes to Apply.
          routes.add(BoardDataRoute(const [], [frame.id]));
        }
      case codingWriteScopeKitId:
        final path = frame.props[writeScopePathProp]?.toString() ?? '';
        final previous =
            before
                .objectById(frame.id)
                ?.props[writeScopePathProp]
                ?.toString() ??
            '';
        if (path.isEmpty || path == previous) break;
        for (final cable in _from(
          cables,
          frame.id,
          KitPortKind.writeScopeOut,
        )) {
          routes.add(_route([cable], 'Write folder selected'));
        }
      case codingCheckSpecKitId:
        final preset = frame.props[checkPresetProp];
        if (preset != gitDiffCheckPreset ||
            preset == before.objectById(frame.id)?.props[checkPresetProp]) {
          break;
        }
        for (final cable in _from(cables, frame.id, KitPortKind.checkSpecOut)) {
          routes.add(_route([cable], 'Check specification selected'));
        }
      case codingCheckResultKitId:
        final body = checkResultBody(after, frame.id);
        final outcome = body?.props['checkOutcome']?.toString() ?? '';
        final prior =
            checkResultBody(
              before,
              frame.id,
            )?.props['checkOutcome']?.toString() ??
            '';
        if (outcome.isEmpty || outcome == prior) break;
        for (final cable in _to(cables, frame.id, KitPortKind.checkResultIn)) {
          routes.add(
            _route(
              [cable],
              outcome == 'running' ? 'Check started' : 'Check result recorded',
            ),
          );
        }
    }
  }
  return routes;
}

/// Apply consumes the settled decision and a live write scope only after the
/// explicit action passes its final checks and attempts the file write.
List<BoardDataRoute> boardDataRoutesForApply(
  SceneDocument document,
  String applyFrameId,
) {
  if (applyPatchGate(document, applyFrameId).inert) return const [];
  final cables = sceneCables(document);
  return [
    for (final cable in cables)
      if (cable.targetFrameId == applyFrameId &&
          (cable.toKind == KitPortKind.applyIn ||
              cable.toKind == KitPortKind.applyWriteScope))
        _route([cable], 'Apply write attempted after verification'),
  ];
}

/// A check consumes its configured preset and write scope only after the
/// explicit run passes its live permission check. Native execution can still
/// report an infrastructure error afterward.
List<BoardDataRoute> boardDataRoutesForCheck(
  SceneDocument document,
  String runFrameId,
) {
  if (!checkGate(document, runFrameId).ready) return const [];
  final cables = sceneCables(document);
  return [
    for (final cable in cables)
      if (cable.targetFrameId == runFrameId &&
          (cable.toKind == KitPortKind.runCheckSpec ||
              cable.toKind == KitPortKind.runCheckWrite))
        _route([cable], 'Run Check requested'),
  ];
}

BoardDataRoute _route(List<SceneCable> cables, String how) => BoardDataRoute(
  [for (final cable in cables) cable.id],
  [cables.first.sourceId, for (final cable in cables) cable.targetFrameId],
  how: how,
);

List<SceneCable> _to(
  List<SceneCable> cables,
  String frameId,
  KitPortKind kind,
) => [
  for (final cable in cables)
    if (cable.targetFrameId == frameId && cable.toKind == kind) cable,
];

List<SceneCable> _from(
  List<SceneCable> cables,
  String frameId,
  KitPortKind kind,
) => [
  for (final cable in cables)
    if (cable.sourceId == frameId && cable.fromKind == kind) cable,
];
