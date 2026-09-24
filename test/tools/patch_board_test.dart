import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/patch/patch_board.dart';

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

      final offer = llmToolOffer(kitApi: kitApi, llmBodyId: llm.last);
      expect(offer.names, contains(proposePatchToolName));
      final tool = offer.tools.singleWhere(
        (item) => item.name == proposePatchToolName,
      );
      final result = await tool.run({'note': 'rename foo to bar'});
      expect(result['ok'], isTrue);
      expect(result['proposalId'], isA<String>());
      expect((result['proposalId'] as String), isNotEmpty);
      expect(result['fingerprint'], isA<String>());
      expect((result['fingerprint'] as String), isNotEmpty);

      final body = patchProposalBody(kitApi.store.document, proposal.first);
      expect(body, isNotNull);
      expect(body!.props[proposalIdProp], result['proposalId']);
      expect(body.props[proposalFingerprintProp], result['fingerprint']);
      expect(body.props['note'], 'rename foo to bar');
      expect(reviewDecisionOf(kitApi.store.document, review.first), isEmpty);
      expect(applyPatchGate(kitApi.store.document, apply.first).inert, isTrue);
      expect(await snapshot(), before);
    },
  );

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

    final created = await proposePatchTool(
      kitApi: kitApi,
      proposeFrameId: propose.first,
    ).run({'note': 'swap one region'});
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
}
