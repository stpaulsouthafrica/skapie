import 'dart:convert';
import 'dart:io';

/// Disk effects live beside the board, outside scene.json and scene undo.
class PatchEffectLog {
  PatchEffectLog({this.file});

  factory PatchEffectLog.besideScene(String? scenePath) => PatchEffectLog(
    file: scenePath == null ? null : File('$scenePath.patch-effects.json'),
  );

  final File? file;
  final List<Map<String, Object?>> _records = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final target = file;
    if (target == null || !await target.exists()) {
      _loaded = true;
      return;
    }
    final decoded = jsonDecode(await target.readAsString());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['records'] is! List) {
      throw const FormatException('Invalid patch effect log');
    }
    final loaded = <Map<String, Object?>>[];
    for (final item in decoded['records'] as List) {
      if (item is Map) {
        loaded.add(item.map((key, value) => MapEntry('$key', value)));
      }
    }
    _records.addAll(loaded);
    _loaded = true;
  }

  List<Map<String, Object?>> get records => List.unmodifiable(_records);

  Map<String, Object?>? latestApplyFor(String applyFrameId) {
    for (final record in _records.reversed) {
      if (record['applyFrameId'] == applyFrameId &&
          record['kind'] == 'apply' &&
          record['state'] == 'applied') {
        return record;
      }
    }
    return null;
  }

  bool wasReverted(String effectId) => _records.any(
    (record) =>
        record['kind'] == 'revert' &&
        record['parentEffectId'] == effectId &&
        record['state'] == 'applied',
  );

  Future<void> append(Map<String, Object?> record) async {
    await load();
    _records.add(record);
    try {
      await _save();
    } catch (_) {
      _records.removeLast();
      rethrow;
    }
  }

  Future<void> update(String id, Map<String, Object?> changes) async {
    await load();
    final index = _records.indexWhere((item) => item['id'] == id);
    if (index < 0) throw StateError('Missing patch effect record');
    final previous = _records[index];
    _records[index] = {..._records[index], ...changes};
    try {
      await _save();
    } catch (_) {
      _records[index] = previous;
      rethrow;
    }
  }

  Future<void> _save() async {
    final target = file;
    if (target == null) return;
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'records': _records})}\n',
      flush: true,
    );
    await temp.rename(target.path);
  }
}
