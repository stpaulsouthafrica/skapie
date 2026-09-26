import 'dart:io';

import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/tools/patch/patch_effect_log.dart';

/// Apply records written before the file was touched. Their outcome is not yet
/// known and must be reconciled against the repository before any retry.
List<Map<String, Object?>> pendingApplyRecords(PatchEffectLog log) => [
  for (final record in log.records)
    if (record['kind'] == 'apply' && record['state'] == 'prepared') record,
];

enum PreparedOutcome { applied, notApplied, uncertain }

/// Compare a prepared apply's expected and previous fingerprints to the file on
/// disk. Reading the repository is the only way to know what happened.
Future<PreparedOutcome> reconcilePreparedApply(
  Map<String, Object?> record,
) async {
  final root = record['root']?.toString() ?? '';
  final relative = record['path']?.toString() ?? '';
  final expected = record['expectedFingerprint']?.toString() ?? '';
  final before = record['beforeFingerprint']?.toString() ?? '';
  if (root.isEmpty || relative.isEmpty || expected.isEmpty) {
    return PreparedOutcome.uncertain;
  }
  final parts = relative.replaceAll('\\', '/').split('/');
  if (parts.any((part) => part.isEmpty || part == '..' || part == '.')) {
    return PreparedOutcome.uncertain;
  }
  final file = File([root, ...parts].join(Platform.pathSeparator));
  if (!await file.exists()) {
    return PreparedOutcome.uncertain;
  }
  final fingerprint = patchByteFingerprint(await file.readAsBytes());
  if (fingerprint == expected) return PreparedOutcome.applied;
  if (fingerprint == before) return PreparedOutcome.notApplied;
  return PreparedOutcome.uncertain;
}

/// Settle every prepared record and return how many were inspected.
Future<int> reconcilePendingApplies(PatchEffectLog log) async {
  final pending = pendingApplyRecords(log);
  for (final record in pending) {
    final outcome = await reconcilePreparedApply(record);
    final state = switch (outcome) {
      PreparedOutcome.applied => 'applied',
      PreparedOutcome.notApplied => 'not_applied',
      PreparedOutcome.uncertain => 'write_uncertain',
    };
    await log.update(record['id']!.toString(), {
      'state': state,
      'reconciledAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
  return pending.length;
}
