import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/openai_compatible.dart';

/// One completion. Context is a system message. Conversation turns keep their roles.
abstract class VanillaSurfaceClient {
  AgentHttpDiagnostic? get lastDiagnostic;

  Future<String> complete({
    required String userText,
    String systemText = '',
    List<ConversationTurn> history = const [],
  });
}
