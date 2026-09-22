import 'package:flutter/foundation.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';
import 'package:skapie/providers/vanilla_client.dart';
import 'package:skapie/tools/attach.dart';

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
  VanillaSurfaceClient? vanilla;
  AgentHttpDiagnostic? lastDiagnostic;
  List<AgentModelInfo> catalogModels = const [];

  /// Body receiving the in-flight Run. Cables that feed it can pulse.
  String? runningBodyId;

  String get statusChip => agentStatusChip(runtime);

  List<AgentModelInfo> get kitModelChoices {
    final connected = [
      for (final model in catalogModels)
        if (model.selectable) model,
    ];
    if (connected.isNotEmpty) {
      return connected;
    }
    return [
      for (final model in opencodeGoCatalog)
        if (model.show)
          AgentModelInfo(
            id: model.id,
            displayName: model.displayName ?? model.id,
            surface: model.surface,
          ),
    ];
  }

  void rememberCatalog(List<AgentModelInfo> models) {
    catalogModels = List<AgentModelInfo>.unmodifiable(models);
    notifyListeners();
  }

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
    vanilla = buildVanillaClient(runtime: resolved, sessionId: session.id);
    runtime = resolved;
    notifyListeners();
  }

  Future<void> useFake() => applySettings(
    providerId: 'fake',
    model: prefs?.model,
    thinkingLevel: prefs?.thinkingLevel,
  );

  /// Selection-scoped vanilla completion onto one compound LLM kit body.
  Future<void> sendUser(String text, {String? targetBodyId}) async {
    final prompt = text.trim();
    final bodyId = targetBodyId?.trim() ?? '';
    if (prompt.isEmpty || bodyId.isEmpty) {
      return;
    }
    final target = kitApi.store.document.objectById(bodyId);
    if (target == null) {
      return;
    }
    runningBodyId = bodyId;
    notifyListeners();
    try {
      await _completeSend(prompt: prompt, bodyId: bodyId);
    } finally {
      runningBodyId = null;
      notifyListeners();
    }
  }

  Future<void> _completeSend({
    required String prompt,
    required String bodyId,
  }) async {
    final target = kitApi.store.document.objectById(bodyId);
    if (target == null) {
      return;
    }
    final kitModel = target.props['model']?.toString().trim() ?? '';
    final kitProvider = target.props['provider']?.toString().trim() ?? '';
    final kitSurface = target.props['surface']?.toString().trim() ?? '';
    final model = kitModel.isNotEmpty ? kitModel : runtime.model;
    final provider = kitProvider.isNotEmpty ? kitProvider : runtime.presetId;
    final document = kitApi.store.document;
    final systemText = llmContextText(document, bodyId);
    final history = llmConversationHistory(document, bodyId);
    final attached = worldToolsForLlm(kitApi: kitApi, llmBodyId: bodyId);
    Object? failure;
    StackTrace? failureTrace;
    String? reply;
    try {
      if (attached.isNotEmpty) {
        final turn = AgentSession(
          model: session.model,
          kitApi: kitApi,
          tools: attached,
          includeTools: true,
          systemPrompt: systemText.trim().isEmpty ? '' : systemText.trim(),
          history: [
            for (final earlier in history)
              AgentMessage(
                role: earlier.role == 'assistant'
                    ? AgentRole.assistant
                    : AgentRole.user,
                content: earlier.content,
              ),
          ],
        );
        await turn.sendUser(prompt);
        reply = turn.messages
            .lastWhere((message) => message.role == AgentRole.assistant)
            .content;
        final sessionModel = session.model;
        if (sessionModel is OpenAiCompatibleAgentModel) {
          lastDiagnostic = sessionModel.lastDiagnostic;
        } else {
          lastDiagnostic = null;
        }
      } else if (runtime.useFake) {
        reply = 'Echo: $prompt';
        lastDiagnostic = null;
      } else {
        final override =
            kitModel.isNotEmpty ||
            kitProvider.isNotEmpty ||
            kitSurface.isNotEmpty;
        final client = override
            ? buildVanillaClient(
                runtime: ResolvedAgentRuntime(
                  presetId: provider,
                  useFake: false,
                  baseUrl: runtime.baseUrl,
                  apiKey: runtime.apiKey,
                  model: model,
                  thinkingLevel: runtime.thinkingLevel,
                  sendKitTools: runtime.sendKitTools,
                ),
                sessionId: session.id,
              )
            : vanilla;
        if (client == null) {
          throw StateError('No vanilla client');
        }
        reply = await client.complete(
          userText: prompt,
          systemText: systemText,
          history: history,
        );
        lastDiagnostic = client.lastDiagnostic;
      }
    } catch (error, stack) {
      failure = error;
      failureTrace = stack;
      final sessionModel = session.model;
      if (sessionModel is OpenAiCompatibleAgentModel &&
          sessionModel.lastDiagnostic != null) {
        lastDiagnostic = sessionModel.lastDiagnostic;
      } else {
        final client = vanilla;
        if (client != null) {
          lastDiagnostic = client.lastDiagnostic;
        }
      }
    }
    publishLlmKit(
      kitApi: kitApi,
      bodyId: bodyId,
      prompt: prompt,
      reply: failure == null ? reply : null,
      error: failure?.toString(),
      model: model,
      provider: provider,
      diagnostic: lastDiagnostic,
      surface: kitSurface.isNotEmpty ? kitSurface : lastDiagnostic?.surface,
    );
    if (failure == null) {
      _appendConversation(
        bodyId: bodyId,
        userText: prompt,
        assistantText: reply ?? '',
      );
    }
    notifyListeners();
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace ?? StackTrace.current);
    }
  }

  void _appendConversation({
    required String bodyId,
    required String userText,
    required String assistantText,
  }) {
    final document = kitApi.store.document;
    for (final frame in conversationFrames(document)) {
      if (!kitHasLink(frame, to: bodyId, port: llmConversationPort)) {
        continue;
      }
      final body = conversationBody(document, frame);
      if (body == null) {
        continue;
      }
      appendConversationExchange(
        kitApi: kitApi,
        bodyId: body.id,
        userText: userText,
        assistantText: assistantText,
      );
    }
  }
}
