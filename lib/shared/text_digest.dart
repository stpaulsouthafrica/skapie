import 'dart:convert';

/// FNV-1a hash of [text] as eight hex digits. Used for change detection when a
/// cryptographic hash is not needed.
String fnv1aHex(String text) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
