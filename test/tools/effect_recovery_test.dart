import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/tools/patch/effect_recovery.dart';
import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/tools/patch/patch_effect_log.dart';

void main() {
  test('a prepared apply is reconciled from the file on disk', () async {
    final root = await Directory.systemTemp.createTemp('skapie-effect-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/note.txt');
    await file.writeAsString('after\n');

    final log = PatchEffectLog(file: File('${root.path}/effects.json'));
    const replacement = 'after\n';
    final before = patchByteFingerprint(utf8.encode('before\n'));
    final expected = patchByteFingerprint(utf8.encode(replacement));
    await log.append({
      'id': 'e1',
      'kind': 'apply',
      'state': 'prepared',
      'root': root.path,
      'path': 'note.txt',
      'beforeFingerprint': before,
      'expectedFingerprint': expected,
    });

    expect(pendingApplyRecords(log), hasLength(1));
    expect(await reconcilePendingApplies(log), 1);
    expect(log.records.single['state'], 'applied');

    // A file still holding the old bytes is safe: nothing was written.
    await file.writeAsString('before\n');
    await log.append({
      'id': 'e2',
      'kind': 'apply',
      'state': 'prepared',
      'root': root.path,
      'path': 'note.txt',
      'beforeFingerprint': before,
      'expectedFingerprint': expected,
    });
    await reconcilePendingApplies(log);
    expect(
      log.records.firstWhere((r) => r['id'] == 'e2')['state'],
      'not_applied',
    );

    // A file that matches neither stays uncertain and needs inspection.
    await file.writeAsString('something else\n');
    await log.append({
      'id': 'e3',
      'kind': 'apply',
      'state': 'prepared',
      'root': root.path,
      'path': 'note.txt',
      'beforeFingerprint': before,
      'expectedFingerprint': expected,
    });
    await reconcilePendingApplies(log);
    expect(
      log.records.firstWhere((r) => r['id'] == 'e3')['state'],
      'write_uncertain',
    );
  });
}
