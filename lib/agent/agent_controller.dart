import 'package:flutter/foundation.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/kit_api/kit_api.dart';

/// Owns the replaceable [AgentSession]. Apply rebuilds it on the same [KitApi].
class AgentController extends ChangeNotifier {
  AgentController({
    required this.kitApi,
    required this.session,
    required this.runtime,
    this.prefsStore,
    this.sources = const AgentRuntimeSources(),
    this.memoryApiKey,
    this.prefs,
  });

  final KitApi kitApi;
  final AgentPrefsStore? prefsStore;
  final AgentRuntimeSources sources;

  AgentSession session;
  ResolvedAgentRuntime runtime;
  String? memoryApiKey;
  AgentPrefs? prefs;

  String get statusChip => agentStatusChip(runtime);

  /// Rebuild the session. Keeps the system prompt; clears prior turns.
  Future<void> applySettings({
    required String providerId,
    String? model,
    String? apiKey,
    String? baseUrl,
  }) async {
    final pasted = apiKey?.trim();
    if (pasted != null && pasted.isNotEmpty) {
      memoryApiKey = pasted;
    }
    final nextPrefs = AgentPrefs(
      providerId: providerId.trim().isEmpty ? 'fake' : providerId.trim(),
      model: model,
      baseUrl: baseUrl,
    );
    prefs = nextPrefs;
    await prefsStore?.save(nextPrefs);
    final resolved = mergeAgentRuntime(
      prefs: nextPrefs,
      memoryApiKey: memoryApiKey,
      sources: sources,
    );
    session = buildAgentSession(kitApi: kitApi, runtime: resolved);
    runtime = resolved;
    notifyListeners();
  }

  Future<void> useFake() => applySettings(providerId: 'fake');
}
