import 'dart:io';

import 'package:flutter/material.dart' show Key, MaterialApp, Scaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/tools/patch/patch_effect_log.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

void main() {
  late KitApi kitApi;
  late Directory scratch;
  late File watched;

  setUp(() async {
    kitApi = createAppKitApi(store: SceneStore());
    scratch = await Directory.systemTemp.createTemp('skapie-11-3-1-');
    watched = File('${scratch.path}/watched.txt');
    await watched.writeAsString('untouched\n');
  });

  tearDown(() async {
    if (await scratch.exists()) {
      await scratch.delete(recursive: true);
    }
  });

  Future<String> snapshot() => watched.readAsString();

  List<String> place(String kitId, Offset origin) =>
      kitApi.instantiate(kitId, origin: origin);

  void cable(
    KitPortKind from,
    String fromFrame,
    KitPortKind to,
    String toFrame,
  ) {
    final ports = kitPorts(kitApi.store.document);
    connectKitPorts(
      kitApi: kitApi,
      from: ports.firstWhere(
        (port) => port.frameId == fromFrame && port.kind == from,
      ),
      to: ports.firstWhere(
        (port) => port.frameId == toFrame && port.kind == to,
      ),
    );
  }

  test('createAppKitApi registers patch and write scope kits', () {
    expect(kitApi.getKit(proposePatchKitId), isNotNull);
    expect(kitApi.getKit(codingPatchProposalKitId), isNotNull);
    expect(kitApi.getKit(codingReviewDecisionKitId), isNotNull);
    expect(kitApi.getKit(codingApplyPatchKitId), isNotNull);
    expect(kitApi.getKit(codingWriteScopeKitId), isNotNull);
    expect(kitApi.getKit(proposePatchKitId)!.displayName, 'Propose Patch');
    expect(
      kitApi.getKit(codingPatchProposalKitId)!.displayName,
      'Patch Proposal',
    );
    expect(
      kitApi.getKit(codingReviewDecisionKitId)!.displayName,
      'Review Decision',
    );
    expect(kitApi.getKit(codingApplyPatchKitId)!.displayName, 'Apply Patch');
  });

  Future<({String applyId, String reviewId, String proposalId, String scopeId})>
  acceptedPatch({String newText = 'changed'}) async {
    final propose = place(proposePatchKitId, Offset.zero);
    final proposal = place(codingPatchProposalKitId, const Offset(280, 0));
    final review = place(codingReviewDecisionKitId, const Offset(560, 0));
    final apply = place(codingApplyPatchKitId, const Offset(840, 0));
    final scope = place(codingWriteScopeKitId, const Offset(840, -160));
    cable(
      KitPortKind.proposalResult,
      propose.first,
      KitPortKind.proposalIn,
      proposal.first,
    );
    cable(
      KitPortKind.proposalOut,
      proposal.first,
      KitPortKind.reviewIn,
      review.first,
    );
    cable(
      KitPortKind.reviewOut,
      review.first,
      KitPortKind.applyIn,
      apply.first,
    );
    cable(
      KitPortKind.writeScopeOut,
      scope.first,
      KitPortKind.applyWriteScope,
      apply.first,
    );
    kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
    final proposed = await proposePatchTool(
      kitApi: kitApi,
      proposeFrameId: propose.first,
      repositoryPath: scratch.path,
      permission: const _AllowRead(),
    ).run({'path': 'watched.txt', 'oldText': 'untouched', 'newText': newText});
    expect(proposed['ok'], isTrue);
    expect(
      recordReviewDecision(
        kitApi: kitApi,
        reviewFrameId: review.first,
        decision: 'accept',
      ),
      isTrue,
    );
    return (
      applyId: apply.first,
      reviewId: review.first,
      proposalId: proposal.first,
      scopeId: scope.first,
    );
  }

  test('patch kit packages parse as four distinct board pieces', () {
    final propose = parseKitPackageJson(
      proposePatchKitJson,
      folderId: proposePatchKitId,
    );
    expect(
      propose.recipe.objects.any(
        (object) => object.props['toolName'] == proposePatchToolName,
      ),
      isTrue,
    );

    final proposal = parseKitPackageJson(
      patchProposalKitJson,
      folderId: codingPatchProposalKitId,
    );
    expect(
      proposal.recipe.objects.any(
        (object) => object.props.containsKey('toolName'),
      ),
      isFalse,
    );

    final review = parseKitPackageJson(
      reviewDecisionKitJson,
      folderId: codingReviewDecisionKitId,
    );
    expect(
      review.recipe.objects.any(
        (object) => object.props.containsKey('toolName'),
      ),
      isFalse,
    );

    final apply = parseKitPackageJson(
      applyPatchKitJson,
      folderId: codingApplyPatchKitId,
    );
    expect(
      apply.recipe.objects.any(
        (object) => object.props.containsKey('toolName'),
      ),
      isFalse,
    );
  });

  test(
    'Propose → Proposal → Review → Apply cables without writing files',
    () async {
      final before = await snapshot();
      final propose = place(proposePatchKitId, Offset.zero);
      final proposal = place(codingPatchProposalKitId, const Offset(280, 0));
      final review = place(codingReviewDecisionKitId, const Offset(560, 0));
      final apply = place(codingApplyPatchKitId, const Offset(840, 0));

      cable(
        KitPortKind.proposalResult,
        propose.first,
        KitPortKind.proposalIn,
        proposal.first,
      );
      cable(
        KitPortKind.proposalOut,
        proposal.first,
        KitPortKind.reviewIn,
        review.first,
      );
      cable(
        KitPortKind.reviewOut,
        review.first,
        KitPortKind.applyIn,
        apply.first,
      );

      final cables = sceneCables(kitApi.store.document);
      expect(cables, hasLength(3));
      expect(
        kitPortsConnect(KitPortKind.proposalResult, KitPortKind.proposalIn),
        isTrue,
      );
      expect(
        kitPortsConnect(KitPortKind.proposalOut, KitPortKind.reviewIn),
        isTrue,
      );
      expect(
        kitPortsConnect(KitPortKind.reviewOut, KitPortKind.applyIn),
        isTrue,
      );
      expect(
        kitPortsConnect(KitPortKind.toolOut, KitPortKind.proposalIn),
        isFalse,
      );
      expect(await snapshot(), before);
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isTrue);
    },
  );

  test(
    'propose_patch creates a proposal artifact and cannot approve or apply',
    () async {
      final before = await snapshot();
      final llm = place(harnessLlmKitId, const Offset(0, 200));
      final repository = place(codingRepositoryKitId, const Offset(0, -160));
      kitApi.updateProps(repository.first, {repositoryPathProp: scratch.path});
      final propose = place(proposePatchKitId, Offset.zero);
      final proposal = place(codingPatchProposalKitId, const Offset(280, 0));
      final review = place(codingReviewDecisionKitId, const Offset(560, 0));
      final apply = place(codingApplyPatchKitId, const Offset(840, 0));
      attachToolKit(
        kitApi: kitApi,
        toolObjectId: propose.first,
        llmBodyId: llm.last,
      );
      cable(
        KitPortKind.repositoryOut,
        repository.first,
        KitPortKind.toolRepository,
        propose.first,
      );
      cable(
        KitPortKind.proposalResult,
        propose.first,
        KitPortKind.proposalIn,
        proposal.first,
      );
      cable(
        KitPortKind.proposalOut,
        proposal.first,
        KitPortKind.reviewIn,
        review.first,
      );
      cable(
        KitPortKind.reviewOut,
        review.first,
        KitPortKind.applyIn,
        apply.first,
      );

      final offer = llmToolOffer(
        kitApi: kitApi,
        llmBodyId: llm.last,
        repositoryPermission: const _AllowRead(),
      );
      expect(offer.names, contains(proposePatchToolName));
      final tool = offer.tools.singleWhere(
        (item) => item.name == proposePatchToolName,
      );
      final result = await tool.run({
        'path': 'watched.txt',
        'oldText': 'untouched',
        'newText': 'renamed',
        'note': 'rename one region',
        'baseHash': 'model-supplied-hash',
      });
      expect(result['ok'], isTrue);
      expect(result['proposalId'], isA<String>());
      expect((result['proposalId'] as String), isNotEmpty);
      expect(result['fingerprint'], isA<String>());
      expect((result['fingerprint'] as String), isNotEmpty);
      expect(result['baseFingerprint'], isNot('model-supplied-hash'));
      expect(result['diff'], contains('+renamed'));

      final body = patchProposalBody(kitApi.store.document, proposal.first);
      expect(body, isNotNull);
      expect(body!.props[proposalIdProp], result['proposalId']);
      expect(body.props[proposalFingerprintProp], result['fingerprint']);
      expect(body.props['note'], 'rename one region');
      expect(body.props['diff'], result['diff']);
      expect(body.props['oldText'], 'untouched');
      expect(body.props['newText'], 'renamed');
      expect(body.props['replacement'], 'renamed\n');
      expect(reviewDecisionOf(kitApi.store.document, review.first), isEmpty);
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isTrue);
      expect(await snapshot(), before);
    },
  );

  test('propose_patch is withheld until a Repository cable exists', () {
    final llm = place(harnessLlmKitId, Offset.zero);
    final propose = place(proposePatchKitId, const Offset(280, 0));
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: propose.first,
      llmBodyId: llm.last,
    );
    final offer = llmToolOffer(kitApi: kitApi, llmBodyId: llm.last);
    expect(offer.names, isNot(contains(proposePatchToolName)));
    expect(
      offer.filtered.any(
        (item) =>
            item.name == proposePatchToolName &&
            item.reason == 'Repository grant missing',
      ),
      isTrue,
    );
  });

  test('Patch Proposal is data and is not offered as a model tool', () {
    final llm = place(harnessLlmKitId, Offset.zero);
    final proposal = place(codingPatchProposalKitId, const Offset(400, 0));
    addKitLink(
      kitApi: kitApi,
      objectId: proposal.first,
      to: llm.last,
      port: llmToolsPort,
    );
    final offer = llmToolOffer(kitApi: kitApi, llmBodyId: llm.last);
    expect(offer.names, isEmpty);
    expect(offer.filtered.any((item) => item.reason == 'Wrong type'), isTrue);
  });

  test('Apply stays inert until a valid review decision exists', () async {
    final before = await snapshot();
    final propose = place(proposePatchKitId, Offset.zero);
    final proposal = place(codingPatchProposalKitId, const Offset(280, 0));
    final review = place(codingReviewDecisionKitId, const Offset(560, 0));
    final apply = place(codingApplyPatchKitId, const Offset(840, 0));
    cable(
      KitPortKind.proposalResult,
      propose.first,
      KitPortKind.proposalIn,
      proposal.first,
    );
    cable(
      KitPortKind.proposalOut,
      proposal.first,
      KitPortKind.reviewIn,
      review.first,
    );
    cable(
      KitPortKind.reviewOut,
      review.first,
      KitPortKind.applyIn,
      apply.first,
    );

    var attempt = await invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: apply.first,
    );
    expect(attempt.inert, isTrue);
    expect(attempt.wrote, isFalse);
    expect(await snapshot(), before);

    final created =
        await proposePatchTool(
          kitApi: kitApi,
          proposeFrameId: propose.first,
          repositoryPath: scratch.path,
          permission: const _AllowRead(),
        ).run({
          'path': 'watched.txt',
          'oldText': 'untouched',
          'newText': 'renamed',
          'note': 'swap one region',
        });
    attempt = await invokeApplyPatch(kitApi: kitApi, applyFrameId: apply.first);
    expect(attempt.inert, isTrue);
    expect(attempt.wrote, isFalse);

    recordReviewDecision(
      kitApi: kitApi,
      reviewFrameId: review.first,
      decision: 'accept',
    );
    expect(applyPatchGate(kitApi.store.document, apply.first).inert, isFalse);
    attempt = await invokeApplyPatch(kitApi: kitApi, applyFrameId: apply.first);
    expect(attempt.inert, isTrue);
    expect(attempt.wrote, isFalse);
    expect(attempt.reason, contains('Write Scope'));
    expect(await snapshot(), before);
    expect(created['ok'], isTrue);
  });

  test(
    'review binds to exact proposal and edits invalidate acceptance',
    () async {
      final before = await snapshot();
      final propose = place(proposePatchKitId, Offset.zero);
      final proposal = place(codingPatchProposalKitId, const Offset(280, 0));
      final review = place(codingReviewDecisionKitId, const Offset(560, 0));
      final apply = place(codingApplyPatchKitId, const Offset(840, 0));
      cable(
        KitPortKind.proposalResult,
        propose.first,
        KitPortKind.proposalIn,
        proposal.first,
      );
      cable(
        KitPortKind.proposalOut,
        proposal.first,
        KitPortKind.reviewIn,
        review.first,
      );
      cable(
        KitPortKind.reviewOut,
        review.first,
        KitPortKind.applyIn,
        apply.first,
      );
      expect(
        recordReviewDecision(
          kitApi: kitApi,
          reviewFrameId: review.first,
          decision: 'accept',
        ),
        isFalse,
      );

      final tool = proposePatchTool(
        kitApi: kitApi,
        proposeFrameId: propose.first,
        repositoryPath: scratch.path,
        permission: const _AllowRead(),
      );
      final first = await tool.run({
        'path': 'watched.txt',
        'oldText': 'untouched',
        'newText': 'first',
      });
      expect(first['ok'], isTrue);
      expect(
        recordReviewDecision(
          kitApi: kitApi,
          reviewFrameId: review.first,
          decision: 'reject',
        ),
        isTrue,
      );
      expect(reviewDecisionOf(kitApi.store.document, review.first), 'reject');
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isTrue);
      expect(await snapshot(), before);

      expect(
        recordReviewDecision(
          kitApi: kitApi,
          reviewFrameId: review.first,
          decision: 'accept',
        ),
        isFalse,
      );
      expect(
        reconsiderReviewDecision(kitApi: kitApi, reviewFrameId: review.first),
        isTrue,
      );
      expect(
        recordReviewDecision(
          kitApi: kitApi,
          reviewFrameId: review.first,
          decision: 'accept',
        ),
        isTrue,
      );
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isFalse);
      expect(await snapshot(), before);

      final body = patchProposalBody(kitApi.store.document, proposal.first)!;
      kitApi.updateProps(body.id, {'newText': 'edited'});
      expect(
        validPatchProposal(
          patchProposalBody(kitApi.store.document, proposal.first),
        ),
        isFalse,
      );
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isTrue);
      expect(
        recordReviewDecision(
          kitApi: kitApi,
          reviewFrameId: review.first,
          decision: 'accept',
        ),
        isFalse,
      );
      expect(await snapshot(), before);

      final second = await tool.run({
        'path': 'watched.txt',
        'oldText': 'untouched',
        'newText': 'second',
      });
      expect(second['proposalId'], isNot(first['proposalId']));
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isTrue);
      expect(
        recordReviewDecision(
          kitApi: kitApi,
          reviewFrameId: review.first,
          decision: 'accept',
        ),
        isTrue,
      );
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isFalse);
      expect(await snapshot(), before);
    },
  );

  testWidgets('Inspector previews diff and records a user review', (
    tester,
  ) async {
    final propose = place(proposePatchKitId, Offset.zero);
    final proposal = place(codingPatchProposalKitId, const Offset(280, 0));
    final review = place(codingReviewDecisionKitId, const Offset(560, 0));
    cable(
      KitPortKind.proposalResult,
      propose.first,
      KitPortKind.proposalIn,
      proposal.first,
    );
    cable(
      KitPortKind.proposalOut,
      proposal.first,
      KitPortKind.reviewIn,
      review.first,
    );
    final result = await tester.runAsync(
      () =>
          proposePatchTool(
            kitApi: kitApi,
            proposeFrameId: propose.first,
            repositoryPath: scratch.path,
            permission: const _AllowRead(),
          ).run({
            'path': 'watched.txt',
            'oldText': 'untouched',
            'newText': 'reviewed',
          }),
    );
    expect(result?['ok'], isTrue);
    final selection = SelectionController()..select(review.first);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(
            store: kitApi.store,
            selection: selection,
            kitApi: kitApi,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('review-open-diff')));
    await tester.tap(find.byKey(const Key('review-open-diff')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('+reviewed'), findsWidgets);
    await tester.tap(find.byKey(const Key('patch-diff-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('review-reject')));
    await tester.tap(find.byKey(const Key('review-reject')));
    await tester.pump();
    expect(reviewDecisionOf(kitApi.store.document, review.first), 'reject');
    expect(find.byKey(const Key('review-accept')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('review-reconsider')));
    await tester.tap(find.byKey(const Key('review-reconsider')));
    await tester.pump();
    await tester.tap(find.text('Reconsider').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('review-accept')));
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pump();
    expect(reviewDecisionOf(kitApi.store.document, review.first), 'accept');
    expect(await tester.runAsync(snapshot), 'untouched\n');
    selection.dispose();
  });

  test(
    'one-region replacement derives a diff and ignores a model hash',
    () async {
      final source = File('${scratch.path}/lib/sample.dart');
      await source.parent.create();
      await source.writeAsString('void foo() {}\n');
      final before = await source.readAsBytes();
      final mode = (await source.stat()).mode;

      final result = await proposeTextReplacement(
        root: scratch.path,
        permission: const _AllowRead(),
        args: {
          'path': 'lib/sample.dart',
          'oldText': 'foo',
          'newText': 'bar',
          'baseHash': 'model-supplied-hash',
        },
      );

      expect(result['ok'], isTrue);
      expect(result['path'], 'lib/sample.dart');
      expect(result['baseFingerprint'], isNot(equals('model-supplied-hash')));
      expect(result['baseFingerprint'], isNotEmpty);
      expect(result['diff'], contains('-void foo() {}'));
      expect(result['diff'], contains('+void bar() {}'));
      expect(await source.readAsBytes(), before);
      expect((await source.stat()).mode, mode);
    },
  );

  test(
    'refuses empty, repeated, outside, binary, symlink, and stale anchors',
    () async {
      final source = File('${scratch.path}/lib/sample.dart');
      await source.parent.create();
      await source.writeAsString('foo foo\n');
      final binary = File('${scratch.path}/blob.bin');
      await binary.writeAsBytes([0, 1, 2, 0]);
      final link = Link('${scratch.path}/alias.dart');
      await link.create(source.path);
      final folderLink = Link('${scratch.path}/linked_lib');
      await folderLink.create(source.parent.path);

      Future<Map<String, Object?>> propose(Map<String, Object?> args) {
        return proposeTextReplacement(
          root: scratch.path,
          permission: const _AllowRead(),
          args: args,
        );
      }

      final empty = await propose({
        'path': 'lib/sample.dart',
        'oldText': '',
        'newText': 'bar',
      });
      final repeated = await propose({
        'path': 'lib/sample.dart',
        'oldText': 'foo',
        'newText': 'bar',
      });
      final outside = await propose({
        'path': '../outside.dart',
        'oldText': 'foo',
        'newText': 'bar',
      });
      final binaryResult = await propose({
        'path': 'blob.bin',
        'oldText': 'foo',
        'newText': 'bar',
      });
      final symlink = await propose({
        'path': 'alias.dart',
        'oldText': 'foo',
        'newText': 'bar',
      });
      final symlinkFolder = await propose({
        'path': 'linked_lib/sample.dart',
        'oldText': 'foo',
        'newText': 'bar',
      });
      final stale = await propose({
        'path': 'lib/sample.dart',
        'oldText': 'missing',
        'newText': 'bar',
      });

      for (final result in [
        empty,
        repeated,
        outside,
        binaryResult,
        symlink,
        symlinkFolder,
        stale,
      ]) {
        expect(result['ok'], isFalse);
        expect((result['reason'] as String).trim(), isNotEmpty);
      }
      expect(empty['reason'], isNot(repeated['reason']));
      expect(await source.readAsString(), 'foo foo\n');
    },
  );

  test('preserves newline style in the derived replacement', () async {
    final source = File('${scratch.path}/crlf.txt');
    await source.writeAsString('line foo\r\n');
    final result = await proposeTextReplacement(
      root: scratch.path,
      permission: const _AllowRead(),
      args: {'path': 'crlf.txt', 'oldText': 'foo', 'newText': 'bar'},
    );
    expect(result['ok'], isTrue);
    expect(result['newline'], 'crlf');
    expect(result['replacement'], 'line bar\r\n');
    expect(await source.readAsString(), 'line foo\r\n');

    final multiline = await proposeTextReplacement(
      root: scratch.path,
      permission: const _AllowRead(),
      args: {'path': 'crlf.txt', 'oldText': 'foo', 'newText': 'bar\nbaz'},
    );
    expect(multiline['ok'], isTrue);
    expect(multiline['replacement'], 'line bar\r\nbaz\r\n');
  });

  test('diff shows the changed region and refuses a no-op', () async {
    await watched.writeAsString('first\nkeep before\nold\nkeep after\nlast\n');
    final proposal = await proposeTextReplacement(
      root: scratch.path,
      permission: const _AllowRead(),
      args: {'path': 'watched.txt', 'oldText': 'old', 'newText': 'new'},
    );
    expect(proposal['ok'], isTrue);
    final diff = proposal['diff']!.toString();
    expect(diff, contains('-old\n+new'));
    expect(diff, isNot(contains('-first')));
    expect(diff, isNot(contains('+last')));
    final noOp = await proposeTextReplacement(
      root: scratch.path,
      permission: const _AllowRead(),
      args: {'path': 'watched.txt', 'oldText': 'old', 'newText': 'old'},
    );
    expect(noOp['ok'], isFalse);
    expect(noOp['reason'], contains('no change'));
  });

  test('refuses a file larger than the host read limit', () async {
    final source = File('${scratch.path}/big.txt');
    await source.writeAsString('${'a' * (2 * 1024 * 1024)}x\n');
    final result = await proposeTextReplacement(
      root: scratch.path,
      permission: const _AllowRead(),
      args: {'path': 'big.txt', 'oldText': 'x', 'newText': 'y'},
    );
    expect(result['ok'], isFalse);
    expect(result['reason'], contains('2 MB'));
    expect(await source.readAsString(), endsWith('x\n'));
  });

  test(
    'Apply needs the separate write grant; export remains available',
    () async {
      final flow = await acceptedPatch();
      final before = await snapshot();
      final effects = PatchEffectLog(
        file: File('${scratch.path}/effects.json'),
      );
      final blocked = await invokeApplyPatch(
        kitApi: kitApi,
        applyFrameId: flow.applyId,
        permission: const _WritePermission(false),
        effects: effects,
      );
      expect(blocked.inert, isTrue);
      expect(blocked.wrote, isFalse);
      expect(await snapshot(), before);
      expect(effects.records, isEmpty);
      final body = patchProposalBody(kitApi.store.document, flow.proposalId)!;
      final exported = await const _WritePermission(false).exportProposal(
        name: 'proposal.json',
        text: body.props['diff']!.toString(),
      );
      expect(exported, 'proposal.json');

      kitApi.updateProps(flow.scopeId, {writeScopePathProp: ''});
      final noStoredPath = await invokeApplyPatch(
        kitApi: kitApi,
        applyFrameId: flow.applyId,
        permission: const _WritePermission(true),
        effects: effects,
      );
      expect(noStoredPath.inert, isTrue);
      expect(await snapshot(), before);
    },
  );

  test('clean Apply records preimage, and Revert is a separate hash-checked effect', () async {
    await watched.writeAsString('untouched\r\n');
    final original = await watched.readAsBytes();
    final mode = (await watched.stat()).mode;
    final flow = await acceptedPatch(newText: 'changed\nagain');
    final logFile = File('${scratch.path}/effects.json');
    final effects = PatchEffectLog(file: logFile);
    final applied = await invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: flow.applyId,
      permission: const _WritePermission(true),
      effects: effects,
    );
    expect(applied.wrote, isTrue);
    expect(await watched.readAsString(), 'changed\r\nagain\r\n');
    expect((await watched.stat()).mode, mode);
    expect(effects.records.single['beforeBytes'], isNotNull);
    expect(effects.records.single['observedDiff'], contains('+changed'));
    expect(await logFile.exists(), isTrue);
    kitApi.store.undo();
    expect(await watched.readAsString(), 'changed\r\nagain\r\n');

    final reopened = PatchEffectLog(file: logFile);
    await reopened.load();
    expect(reopened.records.single['state'], 'applied');
    final reverted = await invokeRevertPatch(
      effects: reopened,
      effectId: applied.effectId!,
      permission: const _WritePermission(true),
      writeScopePath: scratch.path,
    );
    expect(reverted.wrote, isTrue);
    expect(await watched.readAsBytes(), original);
    expect(reopened.records, hasLength(2));
    expect(reopened.records.last['kind'], 'revert');
    expect(reopened.wasReverted(applied.effectId!), isTrue);
  });

  test('Apply refuses to write without a durable effect record', () async {
    final flow = await acceptedPatch();
    final before = await watched.readAsBytes();
    final attempted = await invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: flow.applyId,
      permission: const _WritePermission(true),
    );
    expect(attempted.inert, isTrue);
    expect(attempted.reason, contains('Save this board'));
    expect(await watched.readAsBytes(), before);
  });

  test('stale Apply and stale Revert leave edited files untouched', () async {
    final flow = await acceptedPatch();
    final effects = PatchEffectLog(file: File('${scratch.path}/effects.json'));
    await watched.writeAsString('changed elsewhere\n');
    final stale = await invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: flow.applyId,
      permission: const _WritePermission(true),
      effects: effects,
    );
    expect(stale.conflict, isTrue);
    expect(stale.wrote, isFalse);
    expect(await snapshot(), 'changed elsewhere\n');
    await watched.writeAsString('untouched\n');
    final applied = await invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: flow.applyId,
      permission: const _WritePermission(true),
      effects: effects,
    );
    expect(applied.wrote, isTrue);
    await watched.writeAsString('changed after apply\n');
    final reverted = await invokeRevertPatch(
      effects: effects,
      effectId: applied.effectId!,
      permission: const _WritePermission(true),
      writeScopePath: scratch.path,
    );
    expect(reverted.conflict, isTrue);
    expect(reverted.wrote, isFalse);
    expect(await snapshot(), 'changed after apply\n');
  });

  test('a different Write Scope and an edited proposal cannot Apply', () async {
    final flow = await acceptedPatch();
    final other = await Directory.systemTemp.createTemp('skapie-other-');
    addTearDown(() async => other.delete(recursive: true));
    kitApi.updateProps(flow.scopeId, {writeScopePathProp: other.path});
    final wrongScope = await invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: flow.applyId,
      permission: const _WritePermission(true),
    );
    expect(wrongScope.inert, isTrue);
    expect(wrongScope.wrote, isFalse);
    kitApi.updateProps(flow.scopeId, {writeScopePathProp: scratch.path});
    final body = patchProposalBody(kitApi.store.document, flow.proposalId)!;
    kitApi.updateProps(body.id, {'path': '../outside.txt'});
    final edited = await invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: flow.applyId,
      permission: const _WritePermission(true),
    );
    expect(edited.inert, isTrue);
    expect(edited.wrote, isFalse);
    expect(await snapshot(), 'untouched\n');
  });
}

class _AllowRead implements RepositoryPermission {
  const _AllowRead();

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
  }) async => name;
}
