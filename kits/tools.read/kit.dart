import 'package:skapie_kit/host.dart';

void register() {
  addTool(
    'read',
    'List, search, or read files inside the connected repository. Read-only.',
    '{"type":"object","properties":{"action":{"type":"string","enum":["list","search","read"],"description":"list files, search text, or read one file"},"path":{"type":"string","description":"Repository-relative path for action=read"},"query":{"type":"string","description":"Text to find for action=search"},"startLine":{"type":"integer"},"lineCount":{"type":"integer","description":"At most 200 lines"},"limit":{"type":"integer","description":"Max files for list, up to 500"}},"required":["action"],"additionalProperties":false}',
    'read',
  );
}

String runTool(String name, String argsJson, String contextJson) {
  return '{"__defer":"read","args":' + argsJson + '}';
}
