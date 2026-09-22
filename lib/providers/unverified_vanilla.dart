import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/providers/vanilla_client.dart';

/// Live id with no chart row. Never silently posted as completions.
class UnverifiedVanillaClient implements VanillaSurfaceClient {
  UnverifiedVanillaClient({required this.model, this.presetId});

  final String model;
  final String? presetId;

  @override
  AgentHttpDiagnostic? lastDiagnostic;

  @override
  Future<String> complete({
    required String userText,
    String systemText = '',
    List<ConversationTurn> history = const [],
  }) async {
    lastDiagnostic = AgentHttpDiagnostic(
      presetId: presetId,
      baseUrl: '',
      model: model,
      url: '',
      toolNames: const [],
      reasoningAttached: false,
      surface: 'unverified',
    );
    throw AgentHttpException('Model "$model" is not in the Skapie catalog yet');
  }
}
