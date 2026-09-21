import 'package:flutter/foundation.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/vanilla_completion.dart';
import 'package:skapie/kit_api/kit_api.dart';

/// Owns the replaceable [AgentSession] (later harness) and the vanilla on-ramp.
class AgentController extends ChangeNotifier {
  AgentController({
    required this.kitApi,
    required this.session,
    required this.runtime,
    this.prefsStore,
    this.sources = const AgentRuntimeSources(),
    this.memoryApiKey,
    this.prefs,
    this.vanilla,
  });

  final KitApi kitApi;
  final AgentPrefsStore? prefsStore;
  final AgentRuntimeSources sources;

  AgentSession session;
  ResolvedAgentRuntime runtime;
  String? memoryApiKey;
  AgentPrefs? prefs;
  VanillaCompletionClient? vanilla;
  AgentHttpDiagnostic? lastDiagnostic;

  String get statusChip => agentStatusChip(runtime);

  /// Rebuild the session. Keeps the system prompt; clears prior turns.
  Future<void> applySettings({
    required String providerId,
    String? model,
    String? apiKey,
    String? thinkingLevel,
    bool? sendKitTools,
  }) async {
    final pasted = apiKey?.trim();
    if (pasted != null && pasted.isNotEmpty) {
      memoryApiKey = pasted;
    }
    final keyForRuntime = memoryApiKey ?? pasted;
    final nextPrefs = AgentPrefs(
      providerId: providerId.trim().isEmpty ? 'fake' : providerId.trim(),
      model: model,
      thinkingLevel: thinkingLevel,
      apiKey: keyForRuntime,
      sendKitTools: sendKitTools ?? prefs?.sendKitTools ?? true,
    );
    prefs = nextPrefs;
    await prefsStore?.save(nextPrefs);
    final resolved = mergeAgentRuntime(
      prefs: nextPrefs,
      memoryApiKey: keyForRuntime,
      sources: sources,
    );
    session = buildAgentSession(kitApi: kitApi, runtime: resolved);
    vanilla = buildVanillaCompletion(runtime: resolved, sessionId: session.id);
    runtime = resolved;
    notifyListeners();
  }

  Future<void> useFake() => applySettings(
    providerId: 'fake',
    model: prefs?.model,
    thinkingLevel: prefs?.thinkingLevel,
  );

  /// Chat on-ramp: vanilla completion, then spawn or update the LLM kit.
  Future<void> sendUser(String text) async {
    Object? failure;
    String? reply;
    try {
      if (runtime.useFake) {
        reply = 'Echo: $text';
        lastDiagnostic = null;
      } else {
        final client = vanilla;
        if (client == null) {
          throw StateError('No vanilla completion client');
        }
        reply = await client.complete(userText: text);
        lastDiagnostic = client.lastDiagnostic;
      }
    } catch (error) {
      failure = error;
      final client = vanilla;
      if (client != null) {
        lastDiagnostic = client.lastDiagnostic;
      }
    }
    publishLlmKit(
      kitApi: kitApi,
      prompt: text,
      reply: failure == null ? reply : null,
      error: failure?.toString(),
      model: runtime.model,
      provider: runtime.presetId,
      diagnostic: lastDiagnostic,
    );
    notifyListeners();
    if (failure != null) {
      throw failure;
    }
  }
}
