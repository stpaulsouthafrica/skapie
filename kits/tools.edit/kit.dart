import 'package:skapie_kit/host.dart';

void register() {
  addTool(
    'edit',
    'Replace exact existing text in one repository file. The old text must appear exactly once. Requires a live write grant.',
    '{"type":"object","properties":{"path":{"type":"string","description":"Repository-relative path"},"oldText":{"type":"string","description":"Exact existing text"},"newText":{"type":"string","description":"Replacement text"}},"required":["path","oldText","newText"],"additionalProperties":false}',
    'write',
  );
}

String runTool(String name, String argsJson, String contextJson) {
  return '{"__defer":"edit","args":' + argsJson + '}';
}
