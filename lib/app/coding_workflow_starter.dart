import 'dart:ui';

import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/world/kits.dart';

/// Places the same public kits and typed cables available in the Add palette.
/// No model, patch, or check action is started here.
Rect addCodingWorkflowStarter(KitApi kitApi, {required Offset origin}) {
  if (kitApi.store.document.objects.isNotEmpty) {
    throw StateError('Start on an empty board.');
  }

  const readTools = [
    'repo_list_files',
    'repo_search_text',
    'repo_read_file',
    'repo_git_status',
    'repo_git_diff',
  ];
  final placements = <(String, Offset)>[
    (boardTextKitId, const Offset(0, 0)),
    (harnessLlmKitId, const Offset(700, 0)),
    (harnessConversationKitId, const Offset(1120, 0)),
    (codingRepositoryKitId, const Offset(0, 390)),
    for (var i = 0; i < readTools.length; i++)
      (worldToolKitId(readTools[i]), Offset(350, 350 + i * 105.0)),
    (proposePatchKitId, const Offset(700, 790)),
    (codingPatchProposalKitId, const Offset(1040, 790)),
    (codingReviewDecisionKitId, const Offset(1410, 790)),
    (codingApplyPatchKitId, const Offset(1810, 790)),
    (codingWriteScopeKitId, const Offset(1410, 1030)),
    (codingCheckSpecKitId, const Offset(1410, 1280)),
    (codingRunCheckKitId, const Offset(1810, 1280)),
    (codingCheckResultKitId, const Offset(2190, 1280)),
  ];

  // Check the shelf before mutating the scene. Packages can be reloaded.
  for (final (kitId, _) in placements) {
    if (kitApi.getKit(kitId) == null) {
      throw StateError('Missing public kit: $kitId');
    }
  }

  final frames = <String, String>{};
  for (final (kitId, position) in placements) {
    final ids = kitApi.instantiate(kitId, origin: origin + position);
    frames[kitId] = ids.first;
    if (kitId == boardTextKitId) {
      kitApi.updateProps(ids.last, {'content': ''});
      kitApi.updateProps(ids.first, {kitNameProp: 'Task Text'});
    }
  }

  void wire(
    String sourceKit,
    KitPortKind sourceKind,
    String targetKit,
    KitPortKind targetKind,
  ) {
    final ports = kitPorts(kitApi.store.document);
    final from = ports.singleWhere(
      (port) => port.frameId == frames[sourceKit] && port.kind == sourceKind,
    );
    final to = ports.singleWhere(
      (port) => port.frameId == frames[targetKit] && port.kind == targetKind,
    );
    if (!kitPortsConnect(from.kind, to.kind)) {
      throw StateError('Incompatible public ports: $sourceKit → $targetKit');
    }
    connectKitPorts(kitApi: kitApi, from: from, to: to);
  }

  wire(
    boardTextKitId,
    KitPortKind.textOut,
    harnessLlmKitId,
    KitPortKind.llmInput,
  );
  wire(
    harnessLlmKitId,
    KitPortKind.llmConversation,
    harnessConversationKitId,
    KitPortKind.conversationIn,
  );
  for (final toolName in [...readTools, proposePatchToolName]) {
    final kitId = worldToolKitId(toolName);
    wire(
      codingRepositoryKitId,
      KitPortKind.repositoryOut,
      kitId,
      KitPortKind.toolRepository,
    );
    wire(kitId, KitPortKind.toolOut, harnessLlmKitId, KitPortKind.llmTools);
  }
  wire(
    proposePatchKitId,
    KitPortKind.proposalResult,
    codingPatchProposalKitId,
    KitPortKind.proposalIn,
  );
  wire(
    codingPatchProposalKitId,
    KitPortKind.proposalOut,
    codingReviewDecisionKitId,
    KitPortKind.reviewIn,
  );
  wire(
    codingReviewDecisionKitId,
    KitPortKind.reviewOut,
    codingApplyPatchKitId,
    KitPortKind.applyIn,
  );
  wire(
    codingWriteScopeKitId,
    KitPortKind.writeScopeOut,
    codingApplyPatchKitId,
    KitPortKind.applyWriteScope,
  );
  wire(
    codingWriteScopeKitId,
    KitPortKind.writeScopeOut,
    codingRunCheckKitId,
    KitPortKind.runCheckWrite,
  );
  wire(
    codingCheckSpecKitId,
    KitPortKind.checkSpecOut,
    codingRunCheckKitId,
    KitPortKind.runCheckSpec,
  );
  wire(
    codingRunCheckKitId,
    KitPortKind.runCheckResult,
    codingCheckResultKitId,
    KitPortKind.checkResultIn,
  );

  return Rect.fromLTWH(origin.dx, origin.dy, 2470, 1400);
}
