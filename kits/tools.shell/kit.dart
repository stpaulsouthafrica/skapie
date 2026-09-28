import 'package:skapie_kit/host.dart';

void register() {
  addTool(
    'shell',
    'Run one command with the granted repository as its working folder. Commands that point outside the repository are refused. Requires a live write grant.',
    '{"type":"object","properties":{"command":{"type":"string","description":"Command line to run"}},"required":["command"],"additionalProperties":false}',
    'write',
  );
}

String runTool(String name, String argsJson, String contextJson) {
  return '{"__defer":"shell","args":' + argsJson + '}';
}
