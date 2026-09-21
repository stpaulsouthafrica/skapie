import 'package:skapie/agent/openai_compatible.dart';

/// Vanilla first Enter: user text only. No tools, no system prompt.
abstract class VanillaSurfaceClient {
  AgentHttpDiagnostic? get lastDiagnostic;

  Future<String> complete({required String userText});
}
