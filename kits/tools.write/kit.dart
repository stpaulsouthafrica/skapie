import 'package:skapie_kit/host.dart';

void register() {
  addTool(
    'write',
    'Create or replace one UTF-8 file inside the granted repository. Requires a live write grant. Provide expectedFingerprint to refuse a stale overwrite.',
    '{"type":"object","properties":{"path":{"type":"string","description":"Repository-relative path"},"content":{"type":"string","description":"Full file text"},"expectedFingerprint":{"type":"string","description":"Optional sha256 of the current file before replacing"}},"required":["path","content"],"additionalProperties":false}',
    'write',
  );
}

String runTool(String name, String argsJson, String contextJson) {
  return '{"__defer":"write","args":' + argsJson + '}';
}
