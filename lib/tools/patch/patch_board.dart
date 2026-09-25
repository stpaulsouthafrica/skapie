import 'dart:convert';
import 'dart:io';

import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/tool.dart';

const int proposalTextBound = 256 * 1024;

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
  'description': 'Propose one exact text replacement. Creates a proposal artifact; does not write files.',
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
        'description': 'Propose one exact text replacement. Creates a proposal artifact; does not write files.',
        'requiresRepository': true,
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

Map<String, Object?> _refused(String reason) => {'ok': false, 'reason': reason};

String _byteFingerprint(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _displayDiff(String path, String before, String after) {
  final oldLines = const LineSplitter().convert(before);
  final newLines = const LineSplitter().convert(after);
  final body = StringBuffer()
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path')
    ..writeln('@@ -1,${oldLines.length} +1,${newLines.length} @@');
  for (final line in oldLines) {
    body.writeln('-$line');
  }
  for (final line in newLines) {
    body.writeln('+$line');
  }
  return body.toString();
}

/// One existing UTF-8 file, one exact substring. Reads and fingerprints the
/// file, then derives a display diff. Does not write.
Future<Map<String, Object?>> proposeTextReplacement({
  required String root,
  required RepositoryPermission permission,
  required Map<String, Object?> args,
}) async {
  if (args.containsKey('patch') ||
      args.containsKey('files') ||
      args.containsKey('hunks')) {
    return _refused('Only one exact text replacement is accepted.');
  }
  final relative = args['path']?.toString() ?? '';
  final oldText = args['oldText']?.toString() ?? '';
  final newText = args['newText']?.toString() ?? '';
  if (oldText.isEmpty) {
    return _refused('The existing text anchor is empty.');
  }
  if (oldText.length > proposalTextBound ||
      newText.length > proposalTextBound) {
    return _refused('The anchor or replacement exceeds the text bound.');
  }
  final parts = relative.replaceAll('\\', '/').split('/');
  if (root.trim().isEmpty ||
      relative.trim().isEmpty ||
      relative.startsWith('/') ||
      relative.contains('\u0000') ||
      parts.any((part) => part == '..' || part == '.' || part.isEmpty)) {
    return _refused('Path is outside the repository scope.');
  }
  if (!await permission.canRead(root)) {
    return _refused('Repository access expired. Choose its folder again.');
  }
  final rootDir = Directory(root);
  if (!await rootDir.exists()) {
    return _refused('Repository folder is missing.');
  }
  final canonicalRoot = await rootDir.resolveSymbolicLinks();
  final file = File(
    '$canonicalRoot${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}',
  );
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return _refused('The file is missing, so the content is stale.');
  }
  if (type == FileSystemEntityType.link) {
    return _refused('Symlink targets are not accepted.');
  }
  if (type != FileSystemEntityType.file) {
    return _refused('Only an existing regular file is accepted.');
  }
  final canonical = await file.resolveSymbolicLinks();
  final prefix = '$canonicalRoot${Platform.pathSeparator}';
  if (!canonical.startsWith(prefix)) {
    return _refused('Path is outside the repository scope.');
  }
  final opened = File(canonical);
  if (await opened.length() > 2 * 1024 * 1024) {
    return _refused('File exceeds the 2 MB read limit.');
  }
  final bytes = await opened.readAsBytes();
  if (bytes.contains(0)) {
    return _refused('Binary files are not accepted.');
  }
  String content;
  try {
    content = utf8.decode(bytes);
  } on FormatException {
    return _refused('Only UTF-8 text files are accepted.');
  }
  final first = content.indexOf(oldText);
  if (first < 0) {
    return _refused('The existing text is not in the file, so it is stale.');
  }
  if (content.indexOf(oldText, first + oldText.length) >= 0) {
    return _refused('The existing text matches more than once.');
  }
  final newline = content.contains('\r\n') ? 'crlf' : 'lf';
  final styledNew = newline == 'crlf'
      ? newText.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')
      : newText.replaceAll('\r\n', '\n');
  final replacement = content.replaceRange(
    first,
    first + oldText.length,
    styledNew,
  );
  final mode = (await opened.stat()).mode;
  final fingerprint = _byteFingerprint(bytes);
  return {
    'ok': true,
    'path': parts.join('/'),
    'baseFingerprint': fingerprint,
    'newline': newline,
    'mode': mode,
    'oldText': oldText,
    'newText': styledNew,
    'replacement': replacement,
    'diff': _displayDiff(parts.join('/'), content, replacement),
  };
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
    final diff = proposal['diff']?.toString() ?? '';
    final id = proposal['proposalId']?.toString() ?? '';
    kitApi.updateProps(body.id, {
      proposalIdProp: id,
      proposalFingerprintProp: proposal['fingerprint']?.toString() ?? '',
      'note': note,
      'path': proposal['path']?.toString() ?? '',
      'baseFingerprint': proposal['baseFingerprint']?.toString() ?? '',
      'newline': proposal['newline']?.toString() ?? '',
      'mode': proposal['mode'],
      'diff': diff,
      'oldText': proposal['oldText']?.toString() ?? '',
      'newText': proposal['newText']?.toString() ?? '',
      'replacement': proposal['replacement']?.toString() ?? '',
      'content': diff.trim().isEmpty
          ? (note.trim().isEmpty ? 'Proposal $id' : note)
          : diff,
    });
  }
}

AgentTool proposePatchTool({
  required KitApi kitApi,
  required String proposeFrameId,
  String repositoryPath = '',
  RepositoryPermission permission = const SystemRepositoryPermission(),
}) {
  return AgentTool(
    name: proposePatchToolName,
    description: 'Propose one exact text replacement in an existing repository file. Does not write files or approve the proposal.',
    parameters: jsonSchemaObject(
      properties: {
        'path': {
          'type': 'string',
          'description': 'Repository-relative path of an existing UTF-8 file',
        },
        'oldText': {
          'type': 'string',
          'description': 'Exact existing text to replace, one match only',
        },
        'newText': {
          'type': 'string',
          'description': 'Replacement text for that one match',
        },
        'note': {
          'type': 'string',
          'description': 'What this proposal is about',
        },
      },
      required: const ['path', 'oldText', 'newText'],
    ),
    run: (args) async {
      final note = args['note']?.toString() ?? '';
      final replacement = await proposeTextReplacement(
        root: repositoryPath,
        permission: permission,
        args: args,
      );
      if (replacement['ok'] != true) {
        return replacement;
      }
      final payload = {
        'path': replacement['path'],
        'oldText': replacement['oldText'],
        'newText': replacement['newText'],
        'baseFingerprint': replacement['baseFingerprint'],
        'newline': replacement['newline'],
        'mode': replacement['mode'],
        'note': note,
      };
      final proposal = <String, Object?>{
        'ok': true,
        'proposalId': newSceneId('pp'),
        'fingerprint': proposalFingerprintFor(payload),
        'note': note,
        ...replacement,
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
