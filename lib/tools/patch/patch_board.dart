import 'dart:convert';

import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/tool.dart';

class PatchApplyGate {
  const PatchApplyGate.inert(this.reason) : inert = true;
  const PatchApplyGate.ready() : inert = false, reason = '';

  final bool inert;
  final String reason;
}

class PatchApplyAttempt {
  const PatchApplyAttempt({
    required this.inert,
    required this.wrote,
    required this.reason,
  });

  final bool inert;
  final bool wrote;
  final String reason;
}

Map<String, Object?> get proposePatchKitJson => const {
  'schemaVersion': kitPackageSchemaVersion,
  'id': proposePatchKitId,
  'displayName': 'Propose Patch',
  'description': 'Propose a code change. Creates a proposal artifact; does not write files.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 200,
      'height': proposePatchFrameHeight,
      'props': {
        skapieKitProp: proposePatchKitId,
        skapieRoleProp: 'frame',
        'description': 'Propose a code change. Creates a proposal artifact; does not write files.',
      },
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 36,
      'width': 176,
      'height': 20,
      'props': {
        'content': proposePatchToolName,
        'fontSize': 14,
        'toolName': proposePatchToolName,
        attachedToProp: '',
        skapieKitProp: proposePatchKitId,
        skapieRoleProp: 'grant',
      },
    },
  ],
};

const Map<String, Object?> patchProposalKitJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': codingPatchProposalKitId,
  'displayName': 'Patch Proposal',
  'description': 'Structured proposal data. Not a tool.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': textFrameHeight,
      'props': {
        skapieKitProp: codingPatchProposalKitId,
        skapieRoleProp: 'frame',
      },
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 40,
      'width': 256,
      'height': 48,
      'props': {
        'content': 'No proposal yet',
        'fontSize': 13,
        proposalIdProp: '',
        proposalFingerprintProp: '',
        'note': '',
        skapieKitProp: codingPatchProposalKitId,
        skapieRoleProp: 'body',
      },
    },
  ],
};

const Map<String, Object?> reviewDecisionKitJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': codingReviewDecisionKitId,
  'displayName': 'Review Decision',
  'description': 'A user-owned Accept or Reject. Connecting it does not apply.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': textFrameHeight,
      'props': {
        skapieKitProp: codingReviewDecisionKitId,
        skapieRoleProp: 'frame',
      },
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 40,
      'width': 256,
      'height': 48,
      'props': {
        'content': 'No decision yet',
        'fontSize': 13,
        reviewDecisionProp: '',
        proposalIdProp: '',
        proposalFingerprintProp: '',
        skapieKitProp: codingReviewDecisionKitId,
        skapieRoleProp: 'body',
      },
    },
  ],
};

const Map<String, Object?> applyPatchKitJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': codingApplyPatchKitId,
  'displayName': 'Apply Patch',
  'description': 'Writes only after a valid review decision.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': textFrameHeight,
      'props': {skapieKitProp: codingApplyPatchKitId, skapieRoleProp: 'frame'},
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 40,
      'width': 256,
      'height': 48,
      'props': {
        'content': 'Inert until a valid review decision exists',
        'fontSize': 13,
        skapieKitProp: codingApplyPatchKitId,
        skapieRoleProp: 'body',
      },
    },
  ],
};

KitRecipe _recipeFromPackageJson(Map<String, Object?> json) {
  return parseKitPackageJson(json, folderId: json['id']!.toString()).recipe;
}

KitRecipe get patchProposalRecipe =>
    _recipeFromPackageJson(patchProposalKitJson);
KitRecipe get reviewDecisionRecipe =>
    _recipeFromPackageJson(reviewDecisionKitJson);
KitRecipe get applyPatchRecipe => _recipeFromPackageJson(applyPatchKitJson);

void registerPatchKits(KitApi kitApi) {
  kitApi.registerKit(patchProposalRecipe);
  kitApi.registerKit(reviewDecisionRecipe);
  kitApi.registerKit(applyPatchRecipe);
}

SceneObject? _kitBody(SceneDocument document, SceneObject frame, String kitId) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'body') {
      continue;
    }
    if (kitIdOf(object) != kitId) {
      continue;
    }
    if (kitChildBelongsToFrame(object, frame)) {
      return object;
    }
  }
  return null;
}

SceneObject? _frameById(SceneDocument document, String frameId) {
  return document.objectById(frameId);
}

SceneObject? patchProposalBody(SceneDocument document, String frameId) {
  final frame = _frameById(document, frameId);
  if (frame == null || kitIdOf(frame) != codingPatchProposalKitId) {
    return null;
  }
  return _kitBody(document, frame, codingPatchProposalKitId);
}

SceneObject? reviewDecisionBody(SceneDocument document, String frameId) {
  final frame = _frameById(document, frameId);
  if (frame == null || kitIdOf(frame) != codingReviewDecisionKitId) {
    return null;
  }
  return _kitBody(document, frame, codingReviewDecisionKitId);
}

String reviewDecisionOf(SceneDocument document, String reviewFrameId) {
  return reviewDecisionBody(
        document,
        reviewFrameId,
      )?.props[reviewDecisionProp]?.toString().trim() ??
      '';
}

String proposalFingerprintFor(Map<String, Object?> payload) {
  final canonical = jsonEncode(payload);
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(canonical)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

void writePatchProposal({
  required KitApi kitApi,
  required String proposeFrameId,
  required Map<String, Object?> proposal,
}) {
  final document = kitApi.store.document;
  final owner = document.objectById(proposeFrameId);
  if (owner == null) {
    return;
  }
  for (final link in kitLinksOf(owner)) {
    if (link.port != patchProposalPort) {
      continue;
    }
    final frame = kitFrameForSelection(document: document, selectedId: link.to);
    if (frame == null || kitIdOf(frame) != codingPatchProposalKitId) {
      continue;
    }
    final body = patchProposalBody(document, frame.id);
    if (body == null) {
      continue;
    }
    final note = proposal['note']?.toString() ?? '';
    final id = proposal['proposalId']?.toString() ?? '';
    kitApi.updateProps(body.id, {
      proposalIdProp: id,
      proposalFingerprintProp: proposal['fingerprint']?.toString() ?? '',
      'note': note,
      'content': note.trim().isEmpty ? 'Proposal $id' : note,
    });
  }
}

AgentTool proposePatchTool({
  required KitApi kitApi,
  required String proposeFrameId,
}) {
  return AgentTool(
    name: proposePatchToolName,
    description: 'Propose a code change as a reviewable artifact. Does not write files or approve the proposal.',
    parameters: jsonSchemaObject(
      properties: {
        'note': {
          'type': 'string',
          'description': 'What this proposal is about',
        },
      },
    ),
    run: (args) async {
      final note = args['note']?.toString() ?? '';
      final payload = {'note': note};
      final proposal = <String, Object?>{
        'ok': true,
        'proposalId': newSceneId('pp'),
        'fingerprint': proposalFingerprintFor(payload),
        'note': note,
      };
      writePatchProposal(
        kitApi: kitApi,
        proposeFrameId: proposeFrameId,
        proposal: proposal,
      );
      return proposal;
    },
  );
}

SceneObject? connectedProposalFrame(
  SceneDocument document,
  String reviewFrameId,
) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'frame' ||
        kitIdOf(object) != codingPatchProposalKitId) {
      continue;
    }
    if (kitHasLink(object, to: reviewFrameId, port: patchReviewPort)) {
      return object;
    }
  }
  return null;
}

SceneObject? connectedReviewFrame(SceneDocument document, String applyFrameId) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'frame' ||
        kitIdOf(object) != codingReviewDecisionKitId) {
      continue;
    }
    if (kitHasLink(object, to: applyFrameId, port: patchApplyPort)) {
      return object;
    }
  }
  return null;
}

void recordReviewDecision({
  required KitApi kitApi,
  required String reviewFrameId,
  required String decision,
}) {
  final document = kitApi.store.document;
  final body = reviewDecisionBody(document, reviewFrameId);
  if (body == null) {
    return;
  }
  final proposal = connectedProposalFrame(document, reviewFrameId);
  final proposalBody = proposal == null
      ? null
      : patchProposalBody(document, proposal.id);
  final label = switch (decision) {
    'accept' => 'Accepted',
    'reject' => 'Rejected',
    _ => 'No decision yet',
  };
  kitApi.updateProps(body.id, {
    reviewDecisionProp: decision,
    proposalIdProp: proposalBody?.props[proposalIdProp] ?? '',
    proposalFingerprintProp: proposalBody?.props[proposalFingerprintProp] ?? '',
    'content': label,
  });
}

PatchApplyGate applyPatchGate(SceneDocument document, String applyFrameId) {
  final review = connectedReviewFrame(document, applyFrameId);
  if (review == null) {
    return const PatchApplyGate.inert('No review decision connected');
  }
  if (reviewDecisionOf(document, review.id) != 'accept') {
    return const PatchApplyGate.inert('No valid review decision');
  }
  final proposal = connectedProposalFrame(document, review.id);
  final proposalBody = proposal == null
      ? null
      : patchProposalBody(document, proposal.id);
  final reviewBody = reviewDecisionBody(document, review.id);
  final proposalId = proposalBody?.props[proposalIdProp]?.toString() ?? '';
  final fingerprint =
      proposalBody?.props[proposalFingerprintProp]?.toString() ?? '';
  if (proposalId.isEmpty ||
      fingerprint.isEmpty ||
      proposalId != (reviewBody?.props[proposalIdProp]?.toString() ?? '') ||
      fingerprint !=
          (reviewBody?.props[proposalFingerprintProp]?.toString() ?? '')) {
    return const PatchApplyGate.inert(
      'Review does not match the connected proposal',
    );
  }
  return const PatchApplyGate.ready();
}

Future<PatchApplyAttempt> invokeApplyPatch({
  required KitApi kitApi,
  required String applyFrameId,
}) async {
  final gate = applyPatchGate(kitApi.store.document, applyFrameId);
  if (gate.inert) {
    return PatchApplyAttempt(inert: true, wrote: false, reason: gate.reason);
  }
  return const PatchApplyAttempt(
    inert: false,
    wrote: false,
    reason: 'Apply does not write files until a later write grant exists',
  );
}
