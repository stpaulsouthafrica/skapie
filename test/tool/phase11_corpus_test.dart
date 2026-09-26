import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/tools/patch/patch_effect_log.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

import '../../tool/phase11_corpus.dart';

class _ReadPermission implements RepositoryPermission {
  const _ReadPermission();

  @override
  Future<bool> canRead(String path) async => true;

  @override
  Future<String?> chooseDirectory() async => null;
}

class _WritePermission implements PatchWritePermission {
  const _WritePermission(this.allowed);
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

void main() {
  late Directory scratch;
  late Directory workspace;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('skapie-corpus-');
    workspace = Directory('${scratch.path}/trial');
  });
  tearDown(() async => scratch.delete(recursive: true));

  Future<void> answer(String text) =>
      File('${workspace.path}/answer.txt').writeAsString(text);

  Future<File> sceneWithAcceptedProposal() async {
    final scene = File('${workspace.path}/scene.json');
    await scene.writeAsString(
      jsonEncode({
        'objects': [
          {
            'props': {
              'skapieKit': 'coding.patch_proposal',
              'skapieRole': 'body',
              'proposalId': 'proposal-1',
            },
          },
          {
            'props': {
              'skapieKit': 'coding.review_decision',
              'skapieRole': 'body',
              'decision': 'accept',
              'proposalId': 'proposal-1',
            },
          },
        ],
      }),
    );
    return scene;
  }

  Future<({KitApi api, String applyId, File scene})>
  acceptedBoardPatch() async {
    final api = createAppKitApi(store: SceneStore());
    final propose = api.instantiate(proposePatchKitId, origin: Offset.zero);
    final proposal = api.instantiate(
      codingPatchProposalKitId,
      origin: const Offset(300, 0),
    );
    final review = api.instantiate(
      codingReviewDecisionKitId,
      origin: const Offset(600, 0),
    );
    final apply = api.instantiate(
      codingApplyPatchKitId,
      origin: const Offset(900, 0),
    );
    final scope = api.instantiate(
      codingWriteScopeKitId,
      origin: const Offset(900, 200),
    );
    final repo = Directory('${workspace.path}/repo');
    api.updateProps(scope.first, {writeScopePathProp: repo.path});

    void wire(
      KitPortKind fromKind,
      String fromId,
      KitPortKind toKind,
      String toId,
    ) {
      final ports = kitPorts(api.store.document);
      connectKitPorts(
        kitApi: api,
        from: ports.singleWhere(
          (port) => port.frameId == fromId && port.kind == fromKind,
        ),
        to: ports.singleWhere(
          (port) => port.frameId == toId && port.kind == toKind,
        ),
      );
    }

    wire(
      KitPortKind.proposalResult,
      propose.first,
      KitPortKind.proposalIn,
      proposal.first,
    );
    wire(
      KitPortKind.proposalOut,
      proposal.first,
      KitPortKind.reviewIn,
      review.first,
    );
    wire(KitPortKind.reviewOut, review.first, KitPortKind.applyIn, apply.first);
    wire(
      KitPortKind.writeScopeOut,
      scope.first,
      KitPortKind.applyWriteScope,
      apply.first,
    );
    final result = await proposePatchTool(
      kitApi: api,
      proposeFrameId: propose.first,
      repositoryPath: repo.path,
      permission: const _ReadPermission(),
    ).run({'path': sourcePath, 'oldText': 'value + 2', 'newText': 'value + 1'});
    expect(result['ok'], isTrue);
    expect(
      recordReviewDecision(
        kitApi: api,
        reviewFrameId: review.first,
        decision: 'accept',
      ),
      isTrue,
    );
    final scene = File('${workspace.path}/scene.json');
    await scene.writeAsString(jsonEncode(api.store.document.toJson()));
    return (api: api, applyId: apply.first, scene: scene);
  }

  test('each trial starts with an independent committed repository', () async {
    for (final task in corpusTasks) {
      final one = Directory('${scratch.path}/${task.id}');
      await prepareCorpusTrial(task.id, one);
      expect(
        await File('${one.path}/repo/$sourcePath').readAsString(),
        initialSource,
      );
      expect(await File('${one.path}/answer.txt').readAsString(), isEmpty);
      final status = await Process.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: '${one.path}/repo');
      expect(status.stdout, isEmpty);
    }
    expect(
      () => prepareCorpusTrial(
        'locate_symbol',
        Directory('${scratch.path}/locate_symbol'),
      ),
      throwsStateError,
    );
  });

  test(
    'read-only tasks grade the answer and reject repository changes',
    () async {
      await prepareCorpusTrial('locate_symbol', workspace);
      await answer('increment is at lib/counter.dart:1.');
      expect(
        (await gradeCorpusTrial('locate_symbol', workspace)).passed,
        isTrue,
      );
      await expectLater(
        gradeCorpusTrial('explain_behavior', workspace),
        throwsStateError,
      );
      await File('${workspace.path}/repo/$sourcePath')
          .writeAsString(externalSource);
      expect(
        (await gradeCorpusTrial('locate_symbol', workspace)).passed,
        isFalse,
      );
      final committed = await Process.run('git', [
        'add',
        '--',
        '.',
      ], workingDirectory: '${workspace.path}/repo');
      expect(committed.exitCode, 0);
      final commit = await Process.run('git', [
        'commit',
        '-qm',
        'Change after baseline',
      ], workingDirectory: '${workspace.path}/repo');
      expect(commit.exitCode, 0);
      expect(
        (await gradeCorpusTrial('locate_symbol', workspace)).passed,
        isFalse,
      );

      final explain = Directory('${scratch.path}/explain');
      await prepareCorpusTrial('explain_behavior', explain);
      await File('${explain.path}/answer.txt')
          .writeAsString('increment(3) returns 5; see lib/counter.dart:1.');
      expect(
        (await gradeCorpusTrial('explain_behavior', explain)).passed,
        isTrue,
      );
    },
  );

  test('edit case passes on behavior and one changed source file', () async {
    await prepareCorpusTrial('edit_one_function', workspace);
    await answer('Fixed increment and left decrement alone.');
    expect(
      (await gradeCorpusTrial('edit_one_function', workspace)).passed,
      isFalse,
    );
    await File('${workspace.path}/repo/$sourcePath')
        .writeAsString(initialSource.replaceFirst('value + 2', 'value + 1'));
    expect(
      (await gradeCorpusTrial('edit_one_function', workspace)).passed,
      isTrue,
    );
    await File('${workspace.path}/repo/unrelated.txt').writeAsString('noise');
    expect(
      (await gradeCorpusTrial('edit_one_function', workspace)).passed,
      isFalse,
    );
  });

  test(
    'failed-check case requires failure, later turn, and later pass',
    () async {
      await prepareCorpusTrial('failing_check_revision', workspace);
      await answer(
        'Fixed increment after the check failure; the second check passed.',
      );
      await File('${workspace.path}/repo/$sourcePath')
          .writeAsString(initialSource.replaceFirst('value + 2', 'value + 1'));
      final scene = File('${workspace.path}/scene.json')
        ..writeAsStringSync('{}');
      expect(
        (await gradeCorpusTrial(
          'failing_check_revision',
          workspace,
          sceneFile: scene,
        )).passed,
        isFalse,
      );
      Map<String, Object?> event(
        String at,
        String kind, [
        Map<String, Object?> payload = const {},
      ]) => {'at': at, 'kind': kind, 'payload': payload};
      await File('${scene.path}.runs.json').writeAsString(
        jsonEncode({
          'runs': [
            {
              'kind': 'check',
              'events': [
                event('2026-01-01T00:00:01Z', 'checkFinished', {
                  'outcome': 'nonzero_exit',
                }),
              ],
            },
            {
              'kind': 'agent',
              'events': [event('2026-01-01T00:00:02Z', 'runRequested')],
            },
            {
              'kind': 'check',
              'events': [
                event('2026-01-01T00:00:03Z', 'checkFinished', {
                  'outcome': 'exit_0',
                }),
              ],
            },
          ],
        }),
      );
      final report = await gradeCorpusTrial(
        'failing_check_revision',
        workspace,
        sceneFile: scene,
      );
      expect(report.passed, isTrue);
      expect(report.humanCheck, isNotEmpty);
      final source = File('${workspace.path}/repo/$sourcePath');
      await source.writeAsString(
        (await source.readAsString()).replaceFirst(';\n', ';  \n'),
      );
      final staged = await Process.run('git', [
        'add',
        sourcePath,
      ], workingDirectory: '${workspace.path}/repo');
      expect(staged.exitCode, 0);
      expect(
        (await gradeCorpusTrial(
          'failing_check_revision',
          workspace,
          sceneFile: scene,
        )).passed,
        isFalse,
      );
    },
  );

  test(
    'stale patch keeps external edit and rejects an applied effect',
    () async {
      await prepareCorpusTrial('stale_patch', workspace);
      final scene = await sceneWithAcceptedProposal();
      await answer('Apply refused with a stale-file conflict.');
      await mutateStaleTrial(workspace);
      expect(
        (await gradeCorpusTrial(
          'stale_patch',
          workspace,
          sceneFile: scene,
        )).passed,
        isTrue,
      );
      final originalScene = await scene.readAsString();
      await scene.writeAsString(
        originalScene.replaceFirst(
          '"proposalId":"proposal-1"',
          '"proposalId":"another-proposal"',
        ),
      );
      expect(
        (await gradeCorpusTrial(
          'stale_patch',
          workspace,
          sceneFile: scene,
        )).passed,
        isFalse,
      );
      await scene.writeAsString(originalScene);
      await File('${scene.path}.patch-effects.json').writeAsString(
        jsonEncode({
          'records': [
            {'kind': 'apply', 'state': 'applied'},
          ],
        }),
      );
      expect(
        (await gradeCorpusTrial(
          'stale_patch',
          workspace,
          sceneFile: scene,
        )).passed,
        isFalse,
      );
      await expectLater(() => mutateStaleTrial(workspace), throwsStateError);
    },
  );

  test(
    'permission loss requires an unchanged repo and accepted proposal',
    () async {
      await prepareCorpusTrial('permission_loss', workspace);
      final scene = await sceneWithAcceptedProposal();
      await answer('The live Write Scope permission was unavailable.');
      expect(
        (await gradeCorpusTrial(
          'permission_loss',
          workspace,
          sceneFile: scene,
        )).passed,
        isTrue,
      );
      await File('${workspace.path}/repo/$sourcePath')
          .writeAsString(externalSource);
      expect(
        (await gradeCorpusTrial(
          'permission_loss',
          workspace,
          sceneFile: scene,
        )).passed,
        isFalse,
      );
    },
  );

  test(
    'corpus edit outcome follows the real Propose, Review, Apply path',
    () async {
      await prepareCorpusTrial('edit_one_function', workspace);
      final flow = await acceptedBoardPatch();
      final result = await invokeApplyPatch(
        kitApi: flow.api,
        applyFrameId: flow.applyId,
        permission: const _WritePermission(true),
        effects: PatchEffectLog(
          file: File('${flow.scene.path}.patch-effects.json'),
        ),
      );
      expect(result.wrote, isTrue);
      await answer('I fixed increment while leaving decrement unchanged.');
      expect(
        (await gradeCorpusTrial('edit_one_function', workspace)).passed,
        isTrue,
      );
    },
  );

  test('real Apply refuses a stale file and a missing live grant', () async {
    await prepareCorpusTrial('stale_patch', workspace);
    final stale = await acceptedBoardPatch();
    await mutateStaleTrial(workspace);
    final refused = await invokeApplyPatch(
      kitApi: stale.api,
      applyFrameId: stale.applyId,
      permission: const _WritePermission(true),
      effects: PatchEffectLog(
        file: File('${stale.scene.path}.patch-effects.json'),
      ),
    );
    expect(refused.wrote, isFalse);
    expect(refused.conflict, isTrue);
    await answer('Apply refused because the file became stale.');
    expect(
      (await gradeCorpusTrial(
        'stale_patch',
        workspace,
        sceneFile: stale.scene,
      )).passed,
      isTrue,
    );

    workspace = Directory('${scratch.path}/denied');
    await prepareCorpusTrial('permission_loss', workspace);
    final denied = await acceptedBoardPatch();
    final deniedResult = await invokeApplyPatch(
      kitApi: denied.api,
      applyFrameId: denied.applyId,
      permission: const _WritePermission(false),
      effects: PatchEffectLog(
        file: File('${denied.scene.path}.patch-effects.json'),
      ),
    );
    expect(deniedResult.wrote, isFalse);
    expect(deniedResult.reason, contains('Write Scope'));
    await answer('Apply was blocked because Write Scope permission is gone.');
    expect(
      (await gradeCorpusTrial(
        'permission_loss',
        workspace,
        sceneFile: denied.scene,
      )).passed,
      isTrue,
    );
  });
}
