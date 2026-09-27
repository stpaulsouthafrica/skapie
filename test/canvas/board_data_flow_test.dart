import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/board_data_flow.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/check/check_board.dart';
import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/tools/patch/patch_effect_log.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

class _ReadGrant implements RepositoryPermission {
  @override
  Future<String?> chooseDirectory() async => null;

  @override
  Future<bool> canRead(String path) async => true;
}

class _WriteGrant implements PatchWritePermission {
  const _WriteGrant(this.allowed);
  final bool allowed;

  @override
  Future<bool> canWrite(String path) async => allowed;

  @override
  Future<String?> chooseDirectory() async => null;

  @override
  Future<String?> exportProposal({
    required String name,
    required String text,
  }) async => null;
}

class _ChangingGrant extends _WriteGrant {
  _ChangingGrant(this.onCall) : super(true);

  final void Function(int call) onCall;
  int calls = 0;

  @override
  Future<bool> canWrite(String path) async {
    onCall(++calls);
    return true;
  }
}

class _CheckRunner implements CheckProcessRunner {
  int calls = 0;

  @override
  Future<Map<String, Object?>> runGitDiffCheck(
    String root, {
    void Function(CheckProcessChunk)? onChunk,
  }) async {
    calls++;
    return {'outcome': 'exit_0', 'exitCode': 0};
  }

  @override
  Future<bool> cancel() async => true;
}

void main() {
  late KitApi api;
  late Directory root;

  setUp(() async {
    api = createAppKitApi(includeDemotedKits: true, store: SceneStore());
    root = await Directory.systemTemp.createTemp('skapie-flow-');
    await File('${root.path}/file.txt').writeAsString('before\n');
  });
  tearDown(() async => root.delete(recursive: true));

  String place(String kitId, double x) =>
      api.instantiate(kitId, origin: Offset(x, 0)).first;

  void wire(String source, KitPortKind from, String target, KitPortKind to) {
    final ports = kitPorts(api.store.document);
    connectKitPorts(
      kitApi: api,
      from: ports.singleWhere((p) => p.frameId == source && p.kind == from),
      to: ports.singleWhere((p) => p.frameId == target && p.kind == to),
    );
  }

  test('a successful proposal pulses its actual route to Review', () async {
    final propose = place(proposePatchKitId, 0);
    final proposal = place(codingPatchProposalKitId, 300);
    final review = place(codingReviewDecisionKitId, 600);
    final apply = place(codingApplyPatchKitId, 900);
    wire(propose, KitPortKind.proposalResult, proposal, KitPortKind.proposalIn);
    wire(proposal, KitPortKind.proposalOut, review, KitPortKind.reviewIn);
    wire(review, KitPortKind.reviewOut, apply, KitPortKind.applyIn);
    final cables = sceneCables(api.store.document);
    final inbound = cables.singleWhere(
      (c) => c.toKind == KitPortKind.proposalIn,
    );
    final onward = cables.singleWhere((c) => c.toKind == KitPortKind.reviewIn);
    final accepted = cables.singleWhere((c) => c.toKind == KitPortKind.applyIn);

    final before = api.store.document;
    final result = await proposePatchTool(
      kitApi: api,
      proposeFrameId: propose,
      repositoryPath: root.path,
      permission: _ReadGrant(),
    ).run({'path': 'file.txt', 'oldText': 'before', 'newText': 'after'});
    expect(result['ok'], isTrue);
    final proposed = api.store.document;
    expect(boardDataRoutesForChange(before, proposed), [
      isA<BoardDataRoute>()
          .having((r) => r.cableIds, 'cables', [inbound.id, onward.id])
          .having((r) => r.frameIds, 'frames', [propose, proposal, review]),
    ]);
    expect(boardDataRoutesForChange(proposed, proposed), isEmpty);

    expect(
      recordReviewDecision(
        kitApi: api,
        reviewFrameId: review,
        decision: 'accept',
      ),
      isTrue,
    );
    expect(boardDataRoutesForChange(proposed, api.store.document), [
      isA<BoardDataRoute>().having(
        (r) => r.cableIds,
        'accepted decision cable',
        [accepted.id],
      ),
    ]);
    final settled = api.store.document;
    expect(
      recordReviewDecision(
        kitApi: api,
        reviewFrameId: review,
        decision: 'reject',
      ),
      isFalse,
    );
    expect(boardDataRoutesForChange(settled, api.store.document), isEmpty);
  });

  test(
    'rejection stays at Review; failed proposal creates no transfer',
    () async {
      final propose = place(proposePatchKitId, 0);
      final proposal = place(codingPatchProposalKitId, 300);
      final review = place(codingReviewDecisionKitId, 600);
      final apply = place(codingApplyPatchKitId, 900);
      wire(
        propose,
        KitPortKind.proposalResult,
        proposal,
        KitPortKind.proposalIn,
      );
      wire(proposal, KitPortKind.proposalOut, review, KitPortKind.reviewIn);
      wire(review, KitPortKind.reviewOut, apply, KitPortKind.applyIn);
      final before = api.store.document;
      final failed = await proposePatchTool(
        kitApi: api,
        proposeFrameId: propose,
        repositoryPath: root.path,
        permission: _ReadGrant(),
      ).run({'path': 'file.txt', 'oldText': 'missing', 'newText': 'after'});
      expect(failed['ok'], isFalse);
      expect(boardDataRoutesForChange(before, api.store.document), isEmpty);

      await proposePatchTool(
        kitApi: api,
        proposeFrameId: propose,
        repositoryPath: root.path,
        permission: _ReadGrant(),
      ).run({'path': 'file.txt', 'oldText': 'before', 'newText': 'after'});
      final proposed = api.store.document;
      expect(
        recordReviewDecision(
          kitApi: api,
          reviewFrameId: review,
          decision: 'reject',
        ),
        isTrue,
      );
      final routes = boardDataRoutesForChange(proposed, api.store.document);
      expect(routes, hasLength(1));
      expect(routes.single.cableIds, isEmpty);
      expect(routes.single.frameIds, [review]);
      expect(boardDataRoutesForApply(api.store.document, apply), isEmpty);
    },
  );

  test('Apply input cables pulse only when a verified write starts', () async {
    final propose = place(proposePatchKitId, 0);
    final proposal = place(codingPatchProposalKitId, 300);
    final review = place(codingReviewDecisionKitId, 600);
    final apply = place(codingApplyPatchKitId, 900);
    final scope = place(codingWriteScopeKitId, 900);
    wire(propose, KitPortKind.proposalResult, proposal, KitPortKind.proposalIn);
    wire(proposal, KitPortKind.proposalOut, review, KitPortKind.reviewIn);
    wire(review, KitPortKind.reviewOut, apply, KitPortKind.applyIn);
    wire(scope, KitPortKind.writeScopeOut, apply, KitPortKind.applyWriteScope);
    api.updateProps(scope, {writeScopePathProp: root.path});
    await proposePatchTool(
      kitApi: api,
      proposeFrameId: propose,
      repositoryPath: root.path,
      permission: _ReadGrant(),
    ).run({'path': 'file.txt', 'oldText': 'before', 'newText': 'after'});
    recordReviewDecision(
      kitApi: api,
      reviewFrameId: review,
      decision: 'accept',
    );

    var starts = 0;
    final denied = await invokeApplyPatch(
      kitApi: api,
      applyFrameId: apply,
      permission: const _WriteGrant(false),
      effects: PatchEffectLog(file: File('${root.path}/effects.json')),
      onWriteAttempted: (_) => starts++,
    );
    expect(denied.wrote, isFalse);
    expect(starts, 0);

    final result = await invokeApplyPatch(
      kitApi: api,
      applyFrameId: apply,
      permission: const _WriteGrant(true),
      effects: PatchEffectLog(file: File('${root.path}/effects.json')),
      onWriteAttempted: (id) {
        expect(id, apply);
        expect(boardDataRoutesForApply(api.store.document, id), hasLength(2));
        starts++;
      },
    );
    expect(result.wrote, isTrue);
    expect(starts, 1);
    expect(await File('${root.path}/file.txt').readAsString(), 'after\n');
    final stale = await invokeApplyPatch(
      kitApi: api,
      applyFrameId: apply,
      permission: const _WriteGrant(true),
      effects: PatchEffectLog(file: File('${root.path}/effects.json')),
      onWriteAttempted: (_) => starts++,
    );
    expect(stale.wrote, isFalse);
    expect(starts, 1);
  });

  test('Check input and result pulses follow a real run', () async {
    final spec = place(codingCheckSpecKitId, 0);
    final scope = place(codingWriteScopeKitId, 300);
    final run = place(codingRunCheckKitId, 600);
    final result = place(codingCheckResultKitId, 900);
    wire(spec, KitPortKind.checkSpecOut, run, KitPortKind.runCheckSpec);
    wire(scope, KitPortKind.writeScopeOut, run, KitPortKind.runCheckWrite);
    wire(run, KitPortKind.runCheckResult, result, KitPortKind.checkResultIn);

    final empty = api.store.document;
    api.updateProps(scope, {writeScopePathProp: root.path});
    expect(boardDataRoutesForChange(empty, api.store.document), hasLength(1));
    final scoped = api.store.document;
    api.updateProps(spec, {checkPresetProp: gitDiffCheckPreset});
    expect(boardDataRoutesForChange(scoped, api.store.document), hasLength(1));

    final runner = _CheckRunner();
    final outcomes = <String>[];
    final resultRoutes = <BoardDataRoute>[];
    var last = api.store.document;
    api.store.addListener(() {
      final current = api.store.document;
      resultRoutes.addAll(boardDataRoutesForChange(last, current));
      last = current;
      final outcome =
          checkResultBody(current, result)?.props['checkOutcome']?.toString() ??
          '';
      if (outcome.isNotEmpty && outcome != outcomes.lastOrNull) {
        outcomes.add(outcome);
      }
    });
    var starts = 0;
    final denied = await invokeRunCheck(
      kitApi: api,
      runFrameId: run,
      permission: const _WriteGrant(false),
      runner: runner,
      onRunRequested: (_) => starts++,
    );
    expect(denied.started, isFalse);
    expect(starts, 0);
    expect(runner.calls, 0);
    final attempt = await invokeRunCheck(
      kitApi: api,
      runFrameId: run,
      permission: const _WriteGrant(true),
      runner: runner,
      onRunRequested: (id) {
        expect(id, run);
        expect(boardDataRoutesForCheck(api.store.document, id), hasLength(2));
        starts++;
      },
    );
    expect(attempt.started, isTrue);
    expect(runner.calls, 1);
    expect(starts, 1);
    expect(outcomes, ['running', 'exit_0']);
    final resultCable = sceneCables(api.store.document)
        .singleWhere((cable) => cable.toKind == KitPortKind.checkResultIn);
    expect(resultRoutes.map((route) => route.cableIds), [
      [resultCable.id],
      [resultCable.id],
    ]);
  });

  test('a changed Check setup stops before the run pulse', () async {
    final spec = place(codingCheckSpecKitId, 0);
    final scope = place(codingWriteScopeKitId, 300);
    final run = place(codingRunCheckKitId, 600);
    final result = place(codingCheckResultKitId, 900);
    wire(spec, KitPortKind.checkSpecOut, run, KitPortKind.runCheckSpec);
    wire(scope, KitPortKind.writeScopeOut, run, KitPortKind.runCheckWrite);
    wire(run, KitPortKind.runCheckResult, result, KitPortKind.checkResultIn);
    api.updateProps(spec, {checkPresetProp: gitDiffCheckPreset});
    api.updateProps(scope, {writeScopePathProp: root.path});
    final runner = _CheckRunner();
    var pulses = 0;
    final attempt = await invokeRunCheck(
      kitApi: api,
      runFrameId: run,
      permission: _ChangingGrant((_) {
        api.updateProps(scope, {writeScopePathProp: '${root.path}/other'});
      }),
      runner: runner,
      onRunRequested: (_) => pulses++,
    );
    expect(attempt.started, isFalse);
    expect(pulses, 0);
    expect(runner.calls, 0);
  });

  test('a changed Apply decision stops before the write pulse', () async {
    final propose = place(proposePatchKitId, 0);
    final proposal = place(codingPatchProposalKitId, 300);
    final review = place(codingReviewDecisionKitId, 600);
    final apply = place(codingApplyPatchKitId, 900);
    final scope = place(codingWriteScopeKitId, 900);
    wire(propose, KitPortKind.proposalResult, proposal, KitPortKind.proposalIn);
    wire(proposal, KitPortKind.proposalOut, review, KitPortKind.reviewIn);
    wire(review, KitPortKind.reviewOut, apply, KitPortKind.applyIn);
    wire(scope, KitPortKind.writeScopeOut, apply, KitPortKind.applyWriteScope);
    api.updateProps(scope, {writeScopePathProp: root.path});
    await proposePatchTool(
      kitApi: api,
      proposeFrameId: propose,
      repositoryPath: root.path,
      permission: _ReadGrant(),
    ).run({'path': 'file.txt', 'oldText': 'before', 'newText': 'after'});
    recordReviewDecision(
      kitApi: api,
      reviewFrameId: review,
      decision: 'accept',
    );
    var pulses = 0;
    final attempt = await invokeApplyPatch(
      kitApi: api,
      applyFrameId: apply,
      permission: _ChangingGrant((call) {
        if (call == 2) {
          reconsiderReviewDecision(kitApi: api, reviewFrameId: review);
        }
      }),
      effects: PatchEffectLog(file: File('${root.path}/effects.json')),
      onWriteAttempted: (_) => pulses++,
    );
    expect(attempt.wrote, isFalse);
    expect(pulses, 0);
    expect(await File('${root.path}/file.txt').readAsString(), 'before\n');
  });
}
