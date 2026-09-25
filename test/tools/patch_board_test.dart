import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/patch/patch_board.dart';
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

  test('createAppKitApi registers the four patch board kits', () {
    expect(kitApi.getKit(proposePatchKitId), isNotNull);
    expect(kitApi.getKit(codingPatchProposalKitId), isNotNull);
    expect(kitApi.getKit(codingReviewDecisionKitId), isNotNull);
    expect(kitApi.getKit(codingApplyPatchKitId), isNotNull);
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
    expect(attempt.inert, isFalse);
    expect(attempt.wrote, isFalse);
    expect(await snapshot(), before);
    expect(created['ok'], isTrue);
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
}

class _AllowRead implements RepositoryPermission {
  const _AllowRead();

  @override
  Future<bool> canRead(String path) async => true;

  @override
  Future<String?> chooseDirectory() async => null;
}
