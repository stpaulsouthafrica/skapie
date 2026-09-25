import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/tool.dart';
import 'package:skapie/tools/patch/patch_effect_log.dart';
import 'package:skapie/tools/patch/write_permission.dart';

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
    this.conflict = false,
    this.effectId,
  });

  final bool inert;
  final bool wrote;
  final String reason;
  final bool conflict;
  final String? effectId;
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
  'description':
      'A read-only, one-file patch artifact with a focused diff preview.',
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
  'description': 'A settled user Accept or Reject. Reconsidering requires an explicit action.',
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
  'description': 'Explicitly verifies and writes one file after Accept and a separate Write Scope grant.',
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
        'content': 'Verify and apply one accepted file change',
        'fontSize': 13,
        skapieKitProp: codingApplyPatchKitId,
        skapieRoleProp: 'body',
      },
    },
  ],
};

const Map<String, Object?> writeScopeKitJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': codingWriteScopeKitId,
  'displayName': 'Write Scope',
  'description': 'A separately selected folder with repository write access.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': textFrameHeight,
      'props': {
        skapieKitProp: codingWriteScopeKitId,
        skapieRoleProp: 'frame',
        writeScopePathProp: '',
      },
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 40,
      'width': 256,
      'height': 48,
      'props': {
        'content': 'Choose a folder to grant write access',
        'fontSize': 13,
        skapieKitProp: codingWriteScopeKitId,
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
KitRecipe get writeScopeRecipe => _recipeFromPackageJson(writeScopeKitJson);

void registerPatchKits(KitApi kitApi) {
  kitApi.registerKit(patchProposalRecipe);
  kitApi.registerKit(reviewDecisionRecipe);
  kitApi.registerKit(applyPatchRecipe);
  kitApi.registerKit(writeScopeRecipe);
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
  return sha256.convert(bytes).toString();
}

String _displayDiff(String path, String before, String after) {
  final oldLines = const LineSplitter().convert(before);
  final newLines = const LineSplitter().convert(after);
  var prefix = 0;
  while (prefix < oldLines.length &&
      prefix < newLines.length &&
      oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < oldLines.length - prefix &&
      suffix < newLines.length - prefix &&
      oldLines[oldLines.length - 1 - suffix] ==
          newLines[newLines.length - 1 - suffix]) {
    suffix++;
  }
  final contextStart = (prefix - 2).clamp(0, oldLines.length);
  final contextEndOld = (oldLines.length - suffix + 2).clamp(
    0,
    oldLines.length,
  );
  final contextEndNew = (newLines.length - suffix + 2).clamp(
    0,
    newLines.length,
  );
  final body = StringBuffer()
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path')
    ..writeln(
      '@@ -${contextStart + 1},${contextEndOld - contextStart} +${contextStart + 1},${contextEndNew - contextStart} @@',
    );
  for (var i = contextStart; i < prefix; i++) {
    body.writeln(' ${oldLines[i]}');
  }
  for (var i = prefix; i < oldLines.length - suffix; i++) {
    final line = oldLines[i];
    body.writeln('-$line');
  }
  for (var i = prefix; i < newLines.length - suffix; i++) {
    final line = newLines[i];
    body.writeln('+$line');
  }
  for (var i = oldLines.length - suffix; i < contextEndOld; i++) {
    body.writeln(' ${oldLines[i]}');
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
  var current = canonicalRoot;
  for (final part in parts.take(parts.length - 1)) {
    current = '$current${Platform.pathSeparator}$part';
    final segmentType = await FileSystemEntity.type(
      current,
      followLinks: false,
    );
    if (segmentType == FileSystemEntityType.link) {
      return _refused('Symlink targets are not accepted.');
    }
    if (segmentType != FileSystemEntityType.directory) {
      return _refused('The file is missing, so the content is stale.');
    }
  }
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
  if (replacement == content) {
    return _refused('Replacement makes no change to the file.');
  }
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
  return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
}

/// Fingerprint the fields the engineer actually reviews. Recalculate this from
/// scene data before accepting and before applying, so later edits invalidate
/// a recorded decision even if the stored fingerprint was left untouched.
String proposalContentFingerprint(Map<String, Object?> props) =>
    proposalFingerprintFor({
      for (final key in [
        'path',
        'repositoryPath',
        'baseFingerprint',
        'newline',
        'mode',
        'oldText',
        'newText',
        'replacement',
        'diff',
        'note',
        'content',
      ])
        key: props[key],
    });

bool validPatchProposal(SceneObject? body) {
  if (body == null) return false;
  final props = body.props;
  return (props[proposalIdProp]?.toString().isNotEmpty ?? false) &&
      (props['path']?.toString().isNotEmpty ?? false) &&
      props[proposalFingerprintProp] == proposalContentFingerprint(props);
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
    final update = <String, Object?>{
      proposalIdProp: id,
      'note': note,
      'path': proposal['path']?.toString() ?? '',
      'repositoryPath': proposal['repositoryPath']?.toString() ?? '',
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
    };
    update[proposalFingerprintProp] = proposalContentFingerprint(update);
    kitApi.updateProps(body.id, update);
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
      final diff = replacement['diff']?.toString() ?? '';
      final id = newSceneId('pp');
      final proposal = <String, Object?>{
        'ok': true,
        'proposalId': id,
        'note': note,
        ...replacement,
        'repositoryPath': repositoryPath,
      };
      proposal['fingerprint'] = proposalContentFingerprint({
        ...proposal,
        'content': diff.trim().isEmpty
            ? (note.trim().isEmpty ? 'Proposal $id' : note)
            : diff,
      });
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

bool recordReviewDecision({
  required KitApi kitApi,
  required String reviewFrameId,
  required String decision,
}) {
  final document = kitApi.store.document;
  final body = reviewDecisionBody(document, reviewFrameId);
  if (body == null || (decision != 'accept' && decision != 'reject')) {
    return false;
  }
  final proposal = connectedProposalFrame(document, reviewFrameId);
  final proposalBody = proposal == null
      ? null
      : patchProposalBody(document, proposal.id);
  if (!validPatchProposal(proposalBody)) return false;
  final currentId = body.props[proposalIdProp]?.toString() ?? '';
  final currentFingerprint =
      body.props[proposalFingerprintProp]?.toString() ?? '';
  if (reviewDecisionOf(document, reviewFrameId).isNotEmpty &&
      currentId == proposalBody!.props[proposalIdProp] &&
      currentFingerprint == proposalBody.props[proposalFingerprintProp]) {
    return false;
  }
  final label = switch (decision) {
    'accept' => 'Accepted',
    'reject' => 'Rejected',
    _ => 'No decision yet',
  };
  kitApi.updateProps(body.id, {
    reviewDecisionProp: decision,
    proposalIdProp: proposalBody?.props[proposalIdProp] ?? '',
    proposalFingerprintProp: proposalBody?.props[proposalFingerprintProp] ?? '',
    'reviewedAt': DateTime.now().toUtc().toIso8601String(),
    'content': label,
  });
  return true;
}

bool reconsiderReviewDecision({
  required KitApi kitApi,
  required String reviewFrameId,
}) {
  final body = reviewDecisionBody(kitApi.store.document, reviewFrameId);
  if (body == null ||
      reviewDecisionOf(kitApi.store.document, reviewFrameId).isEmpty) {
    return false;
  }
  kitApi.updateProps(body.id, {
    reviewDecisionProp: '',
    proposalIdProp: '',
    proposalFingerprintProp: '',
    'reviewedAt': '',
    'content': 'Ready to review',
  });
  return true;
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
  if (!validPatchProposal(proposalBody) ||
      proposalId.isEmpty ||
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
  PatchWritePermission permission = const SystemPatchWritePermission(),
  PatchEffectLog? effects,
}) async {
  try {
    return await _invokeApplyPatch(
      kitApi: kitApi,
      applyFrameId: applyFrameId,
      permission: permission,
      effects: effects,
    );
  } catch (error) {
    return PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: 'Apply stopped during verification: $error',
    );
  }
}

Future<PatchApplyAttempt> _invokeApplyPatch({
  required KitApi kitApi,
  required String applyFrameId,
  required PatchWritePermission permission,
  required PatchEffectLog? effects,
}) async {
  final gate = applyPatchGate(kitApi.store.document, applyFrameId);
  if (gate.inert) {
    return PatchApplyAttempt(inert: true, wrote: false, reason: gate.reason);
  }
  final document = kitApi.store.document;
  final scope = connectedWriteScopeFrame(document, applyFrameId);
  final scopePath = scope?.props[writeScopePathProp]?.toString().trim() ?? '';
  if (scopePath.isEmpty || !await permission.canWrite(scopePath)) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      reason: 'Choose and connect a live Write Scope before Apply.',
    );
  }
  final review = connectedReviewFrame(document, applyFrameId)!;
  final proposal = connectedProposalFrame(document, review.id)!;
  final body = patchProposalBody(document, proposal.id)!;
  final props = body.props;
  final proposalRoot = props['repositoryPath']?.toString() ?? '';
  if (proposalRoot.isEmpty ||
      await Directory(proposalRoot).resolveSymbolicLinks() !=
          await Directory(scopePath).resolveSymbolicLinks()) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      reason: 'Write Scope does not match the proposed repository.',
    );
  }
  final path = props['path']?.toString() ?? '';
  File file;
  try {
    file = await _scopedExistingFile(scopePath, path);
  } catch (error) {
    return PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: '$error',
    );
  }
  final current = await file.readAsBytes();
  final base = props['baseFingerprint']?.toString() ?? '';
  if (current.length > 2 * 1024 * 1024 || _byteFingerprint(current) != base) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: 'Conflict: the file changed since this proposal. Review a new proposal.',
    );
  }
  final replacement = props['replacement']?.toString() ?? '';
  final oldText = props['oldText']?.toString() ?? '';
  final newText = props['newText']?.toString() ?? '';
  String original;
  try {
    original = utf8.decode(current);
  } on FormatException {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: 'Conflict: the file is no longer UTF-8 text.',
    );
  }
  final first = original.indexOf(oldText);
  if (oldText.isEmpty ||
      first < 0 ||
      original.indexOf(oldText, first + oldText.length) >= 0 ||
      original.replaceRange(first, first + oldText.length, newText) !=
          replacement) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: 'Conflict: the replacement no longer applies exactly.',
    );
  }
  final mode = (await file.stat()).mode;
  if (mode != props['mode']) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: 'Conflict: file permissions changed since this proposal.',
    );
  }
  final log = effects ?? PatchEffectLog.besideScene(kitApi.store.sceneFilePath);
  if (log.file == null) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      reason:
          'Save this board before Apply so the file effect can be recorded.',
    );
  }
  final id = newSceneId('effect');
  final nextBytes = utf8.encode(replacement);
  final record = <String, Object?>{
    'id': id,
    'kind': 'apply',
    'state': 'prepared',
    'applyFrameId': applyFrameId,
    'proposalId': props[proposalIdProp],
    'proposalFingerprint': props[proposalFingerprintProp],
    'root': scopePath,
    'path': path,
    'beforeBytes': base64Encode(current),
    'beforeFingerprint': base,
    'expectedFingerprint': _byteFingerprint(nextBytes),
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  };
  var preimageRecorded = false;
  try {
    await log.append(record); // Preserve the preimage before touching disk.
    preimageRecorded = true;
    file = await _scopedExistingFile(scopePath, path);
    if (_byteFingerprint(await file.readAsBytes()) != base ||
        !await permission.canWrite(scopePath)) {
      await log.update(id, {'state': 'conflict'});
      return const PatchApplyAttempt(
        inert: true,
        wrote: false,
        conflict: true,
        reason: 'Conflict: the target changed immediately before writing.',
      );
    }
    await file.writeAsBytes(nextBytes, flush: true);
    final observed = await file.readAsBytes();
    final observedFingerprint = _byteFingerprint(observed);
    await log.update(id, {
      'state': observedFingerprint == _byteFingerprint(nextBytes)
          ? 'applied'
          : 'write_uncertain',
      'afterFingerprint': observedFingerprint,
      'observedDiff': _displayDiff(path, original, utf8.decode(observed)),
      'finishedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return PatchApplyAttempt(
      inert: false,
      wrote: observedFingerprint == _byteFingerprint(nextBytes),
      effectId: id,
      reason: observedFingerprint == _byteFingerprint(nextBytes)
          ? 'Applied one file. The observed diff is recorded.'
          : 'Write result differs from the proposal; inspect the file.',
    );
  } catch (error) {
    return PatchApplyAttempt(
      inert: !preimageRecorded,
      wrote: false,
      effectId: preimageRecorded ? id : null,
      reason: preimageRecorded
          ? 'Write failed or is uncertain: $error'
          : 'Could not record the preimage; no file was written: $error',
    );
  }
}

SceneObject? connectedWriteScopeFrame(
  SceneDocument document,
  String applyFrameId,
) {
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] == 'frame' &&
        kitIdOf(object) == codingWriteScopeKitId &&
        kitHasLink(object, to: applyFrameId, port: writeScopePort)) {
      return object;
    }
  }
  return null;
}

Future<File> _scopedExistingFile(String root, String relative) async {
  final parts = relative.replaceAll('\\', '/').split('/');
  if (root.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('\u0000') ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw StateError('Conflict: path is outside the Write Scope.');
  }
  final canonicalRoot = await Directory(root).resolveSymbolicLinks();
  var current = canonicalRoot;
  for (final part in parts.take(parts.length - 1)) {
    current = '$current${Platform.pathSeparator}$part';
    if (await FileSystemEntity.type(current, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Conflict: parent folder is missing or is a symlink.');
    }
  }
  final path =
      '$canonicalRoot${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}';
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError(
      'Conflict: target is missing, changed type, or is a symlink.',
    );
  }
  final canonical = await File(path).resolveSymbolicLinks();
  if (!canonical.startsWith('$canonicalRoot${Platform.pathSeparator}')) {
    throw StateError('Conflict: path is outside the Write Scope.');
  }
  return File(canonical);
}

Future<PatchApplyAttempt> invokeRevertPatch({
  required PatchEffectLog effects,
  required String effectId,
  required PatchWritePermission permission,
  required String writeScopePath,
}) async {
  try {
    return await _invokeRevertPatch(
      effects: effects,
      effectId: effectId,
      permission: permission,
      writeScopePath: writeScopePath,
    );
  } catch (error) {
    return PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: 'Revert stopped during verification: $error',
    );
  }
}

Future<PatchApplyAttempt> _invokeRevertPatch({
  required PatchEffectLog effects,
  required String effectId,
  required PatchWritePermission permission,
  required String writeScopePath,
}) async {
  if (effects.file == null) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      reason: 'Revert needs the saved file effect record.',
    );
  }
  await effects.load();
  Map<String, Object?>? source;
  for (final record in effects.records) {
    if (record['id'] == effectId &&
        record['kind'] == 'apply' &&
        record['state'] == 'applied') {
      source = record;
    }
  }
  if (source == null || effects.wasReverted(effectId)) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      reason: 'No applied effect is available to revert.',
    );
  }
  final root = source['root']?.toString() ?? '';
  final path = source['path']?.toString() ?? '';
  if (root.isEmpty ||
      writeScopePath.isEmpty ||
      await Directory(root).resolveSymbolicLinks() !=
          await Directory(writeScopePath).resolveSymbolicLinks() ||
      !await permission.canWrite(writeScopePath)) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      reason: 'The separate Write Scope grant is missing.',
    );
  }
  File file;
  try {
    file = await _scopedExistingFile(root, path);
  } catch (error) {
    return PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason: '$error',
    );
  }
  final current = await file.readAsBytes();
  if (_byteFingerprint(current) != source['afterFingerprint']) {
    return const PatchApplyAttempt(
      inert: true,
      wrote: false,
      conflict: true,
      reason:
          'Conflict: file changed after Apply. Revert did not overwrite it.',
    );
  }
  final before = base64Decode(source['beforeBytes']?.toString() ?? '');
  final revertId = newSceneId('effect');
  await effects.append({
    'id': revertId,
    'kind': 'revert',
    'state': 'prepared',
    'parentEffectId': effectId,
    'applyFrameId': source['applyFrameId'],
    'root': root,
    'path': path,
    'beforeBytes': base64Encode(current),
    'beforeFingerprint': _byteFingerprint(current),
    'expectedFingerprint': _byteFingerprint(before),
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
  try {
    file = await _scopedExistingFile(root, path);
    if (_byteFingerprint(await file.readAsBytes()) !=
            source['afterFingerprint'] ||
        !await permission.canWrite(root)) {
      await effects.update(revertId, {'state': 'conflict'});
      return const PatchApplyAttempt(
        inert: true,
        wrote: false,
        conflict: true,
        reason: 'Conflict: file changed immediately before Revert.',
      );
    }
    await file.writeAsBytes(before, flush: true);
    final observed = await file.readAsBytes();
    final restored = _byteFingerprint(observed) == source['beforeFingerprint'];
    await effects.update(revertId, {
      'state': restored ? 'applied' : 'write_uncertain',
      'afterFingerprint': _byteFingerprint(observed),
      'observedDiff': _displayDiff(
        path,
        utf8.decode(current),
        utf8.decode(observed),
      ),
      'finishedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return PatchApplyAttempt(
      inert: false,
      wrote: restored,
      effectId: revertId,
      reason: restored
          ? 'Restored the recorded preimage.'
          : 'Revert result is uncertain.',
    );
  } catch (error) {
    return PatchApplyAttempt(
      inert: false,
      wrote: false,
      effectId: revertId,
      reason: 'Revert failed or is uncertain: $error',
    );
  }
}
