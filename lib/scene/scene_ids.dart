import 'dart:math';

String newSceneId([String prefix = 's']) {
  final n = DateTime.now().microsecondsSinceEpoch;
  final r = Random().nextInt(0x7fffffff);
  return '${prefix}_${n.toRadixString(16)}_$r';
}
