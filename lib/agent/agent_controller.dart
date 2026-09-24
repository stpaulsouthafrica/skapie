import 'package:flutter/foundation.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/llm_run_use.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/agent/run_route.dart';
import 'package:skapie/agent/messages_agent_model.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/responses_agent_model.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/providers/model_surface.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';
import 'package:skapie/providers/vanilla_client.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

enum AgentToolActivityState { running, completed, failed }

class AgentToolActivity {
  const AgentToolActivity({
    required this.callId,
    required this.name,
    required this.argumentsJson,
    required this.state,
    this.result,
  });

  final String callId;
  final String name;
  final String argumentsJson;
  final AgentToolActivityState state;
  final String? result;
}

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
    this.repositoryPermission = const SystemRepositoryPermission(),
    RunLedger? ledger,
    this.ledgerFile,
  }) : ledger = ledger ?? RunLedger();

  final KitApi kitApi;
  final AgentPrefsStore? prefsStore;
  final AgentRuntimeSources sources;
  final RepositoryPermission repositoryPermission;
  final RunLedger ledger;
  final RunLedgerFile? ledgerFile;
  Future<void> _ledgerWrites = Future.value();
  String? _activeRunId;
  _RunCancel? _gate;

  AgentSession session;
  ResolvedAgentRuntime runtime;
  String? memoryApiKey;
  AgentPrefs? prefs;
  VanillaSurfaceClient? vanilla;
  AgentHttpDiagnostic? lastDiagnostic;
  List<AgentModelInfo> catalogModels = const [];

  /// Body receiving the in-flight Run.
  String? runningBodyId;

  /// Ports read for [runningBodyId]: input, context, conversation.
  Set<String> seedPorts = const {};
  DateTime? _runStartedAt;

  /// Tool frame executing a call. Null when no call is in flight.
  String? activeToolFrameId;

  /// Last tool start. The cable layer plays this even if the call already ended.
  int toolPulse = 0;
  String? toolPulseFrameId;
  String? toolPulseBodyId;

  /// Last tool result. The cable layer flashes back toward the LLM.
  int toolResultPulse = 0;
  String? toolResultFrameId;
  String? toolResultBodyId;

  /// Increments when a reply is written. The viewport plays one output flash.
  int outputPulse = 0;
  String? outputBodyId;

  /// Kits and cables Identify is lighting. Null when the board is at rest.
  RunTrace? trace;
  int _traceToken = 0;
  final Map<String, List<AgentToolActivity>> _toolActivities = {};
  final Map<String, LlmRunUse> _runUse = {};

  /// Each LLM's latest run this session. Not persisted.
  Map<String, LlmRunUse> get lastRunUse => Map.unmodifiable(_runUse);

  List<AgentToolActivity> toolActivitiesFor(String bodyId) =>
      List.unmodifiable(_toolActivities[bodyId] ?? const <AgentToolActivity>[]);

  RunRecord? latestRunFor(String bodyId) {
    final runs = ledger.runsFor(bodyId);
    if (runs.isEmpty) {
      return null;
    }
    return runs.last;
  }

  /// Stops the in-flight run. Further model and tool work is abandoned.
  void interruptRun() {
    final gate = _gate;
    final runId = _activeRunId;
    if (gate == null || runId == null || gate.cancelled) {
      return;
    }
    gate.cancelled = true;
    _note(
      runId,
      RunEventKind.runInterrupted,
      const {},
      routeForKit(kitApi.store.document, runningBodyId ?? ''),
    );
    runningBodyId = null;
    activeToolFrameId = null;
    seedPorts = const {};
    notifyListeners();
  }

  Future<void> flushLedger() => _ledgerWrites;

  Future<void> loadLedger() async {
    final file = ledgerFile;
    if (file == null) {
      return;
    }
    await file.loadInto(ledger);
    if (ledger.closedIncomplete) {
      _ledgerWrites = _ledgerWrites.then((_) => file.write(ledger));
      await _ledgerWrites;
    }
    notifyListeners();
  }

  void clearTrace() {
    _traceToken++;
    if (trace == null) {
      return;
    }
    trace = null;
    notifyListeners();
  }

  /// Lights every kit and cable in the run, and dims the rest.
  /// The board eases in for half a second, holds for three, then eases out.
  Future<void> identifyRun(RunRecord run) async {
    final token = ++_traceToken;
    trace = RunTrace.ensemble(run);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    if (_traceToken != token) {
      return;
    }
    trace = null;
    notifyListeners();
  }

  void _note(
    String runId,
    RunEventKind kind, [
    Map<String, Object?> payload = const {},
    RunRoute? route,
  ]) {
    final event = ledger.append(runId, kind, {...payload, ...?route?.fields});
    if (event == null) {
      return;
    }
    final file = ledgerFile;
    if (file != null) {
      _ledgerWrites = _ledgerWrites.then((_) => file.write(ledger));
    }
    notifyListeners();
  }

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
    final blockers = [
      for (final issue in validateBoard(
        kitApi.store.document,
      ).runBlockers(bodyId, inputSupplied: true))
        if (issue.kind != BoardIssueKind.missingGrant) issue,
    ];
    if (blockers.isNotEmpty) {
      return;
    }
    final target = kitApi.store.document.objectById(bodyId);
    if (target == null) {
      return;
    }
    runningBodyId = bodyId;
    final gate = _RunCancel();
    _gate = gate;
    final run = ledger.begin(bodyId: bodyId);
    _activeRunId = run.id;
    _runStartedAt = DateTime.now();
    activeToolFrameId = null;
    seedPorts = _seedPortsFor(bodyId);
    _toolActivities[bodyId] = [];
    _runUse[bodyId] = LlmRunUse(
      bodyId: bodyId,
      startedAt: _runStartedAt!,
      readPorts: seedPorts,
      readConversation: llmConversationHistory(
        kitApi.store.document,
        bodyId,
      ).isNotEmpty,
    );
    final into = _modelRoute(bodyId);
    _note(run.id, RunEventKind.runRequested, {'bodyId': bodyId}, into);
    _note(run.id, RunEventKind.graphValidated, {'ok': true}, into);
    notifyListeners();
    Object? failure;
    StackTrace? failureTrace;
    try {
      await _completeSend(
        prompt: prompt,
        bodyId: bodyId,
        runId: run.id,
        gate: gate,
      );
    } catch (error, stack) {
      failure = error;
      failureTrace = stack;
      if (!gate.cancelled) {
        _note(run.id, RunEventKind.runFailed, {
          'error': '$error',
        }, _modelRoute(bodyId));
      }
    } finally {
      if (gate.cancelled) {
        _note(run.id, RunEventKind.runInterrupted);
      } else if (failure == null) {
        _note(
          run.id,
          RunEventKind.runCompleted,
          const {},
          routeForReply(document: kitApi.store.document, bodyId: bodyId),
        );
      }
      _runUse[bodyId]?.finishedAt = DateTime.now();
      if (identical(_gate, gate)) {
        runningBodyId = null;
        activeToolFrameId = null;
        seedPorts = const {};
        _activeRunId = null;
        _gate = null;
      }
      notifyListeners();
    }
    if (failure != null && !gate.cancelled) {
      Error.throwWithStackTrace(failure, failureTrace ?? StackTrace.current);
    }
  }

  RunRoute _modelRoute(String bodyId) {
    final use = _runUse[bodyId];
    return routeIntoModel(
      document: kitApi.store.document,
      bodyId: bodyId,
      ports: use?.readPorts ?? seedPorts,
      conversation: use?.readConversation ?? false,
    );
  }

  Set<String> _seedPortsFor(String bodyId) {
    final document = kitApi.store.document;
    final ports = <String>{};
    if (llmCableInput(document, bodyId).trim().isNotEmpty) {
      ports.add(llmInputPort);
    }
    if (llmContextText(document, bodyId).trim().isNotEmpty) {
      ports.add(llmContextPort);
    }
    return Set.unmodifiable(ports);
  }

  void _showOutput(String bodyId) {
    outputBodyId = bodyId;
    outputPulse++;
    notifyListeners();
  }

  Future<void> _completeSend({
    required String prompt,
    required String bodyId,
    required String runId,
    required _RunCancel gate,
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
    final offer = llmToolOffer(
      kitApi: kitApi,
      llmBodyId: bodyId,
      repositoryPermission: repositoryPermission,
    );
    final attached = offer.tools;
    final callFacts = <String, Object?>{
      'offeredTools': offer.names,
      'toolSchemaDigest': offer.schemaDigest,
      'filteredTools': [for (final tool in offer.filtered) tool.toJson()],
      'model': model ?? '',
      'provider': provider,
    };
    agentHttpRequestObserver = (request) {
      if (gate.cancelled) {
        return;
      }
      _note(runId, RunEventKind.modelRequestStarted, {
        ...callFacts,
        'request': request,
      }, _modelRoute(bodyId));
    };
    Object? failure;
    StackTrace? failureTrace;
    String? reply;
    int? plainElapsed;
    try {
      if (attached.isNotEmpty) {
        final turnModel = _modelForKit(session.model, model);
        final turn = AgentSession(
          model: _RunLedgerModel(
            inner: turnModel,
            onRequest:
                (
                  finished, {
                  required bool ok,
                  String? response,
                  int? elapsedMs,
                  String? error,
                }) {
                  if (gate.cancelled || !finished) {
                    return;
                  }
                  _note(
                    runId,
                    RunEventKind.modelRequestFinished,
                    _finishedCall(
                      callFacts,
                      ok: ok,
                      response: response,
                      elapsedMs: elapsedMs,
                      error: error,
                    ),
                    _modelRoute(bodyId),
                  );
                },
          ),
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
        final events = turn.events.listen(
          (event) => _recordToolEvent(bodyId, event),
        );
        try {
          await turn.sendUser(prompt, isCancelled: () => gate.cancelled);
        } finally {
          await events.cancel();
        }
        reply = turn.messages
            .lastWhere((message) => message.role == AgentRole.assistant)
            .content;
        lastDiagnostic = switch (turnModel) {
          OpenAiCompatibleAgentModel completions => completions.lastDiagnostic,
          OpenAiResponsesAgentModel responses => responses.lastDiagnostic,
          OpenAiMessagesAgentModel messages => messages.lastDiagnostic,
          _ => null,
        };
      } else if (runtime.useFake) {
        final watch = Stopwatch()..start();
        _note(
          runId,
          RunEventKind.modelRequestStarted,
          callFacts,
          _modelRoute(bodyId),
        );
        reply = 'Echo: $prompt';
        watch.stop();
        plainElapsed = watch.elapsedMilliseconds;
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
        final watch = Stopwatch()..start();
        if (client == null) {
          _note(
            runId,
            RunEventKind.modelRequestStarted,
            callFacts,
            _modelRoute(bodyId),
          );
          throw StateError('No vanilla client');
        }
        reply = await client.complete(
          userText: prompt,
          systemText: systemText,
          history: history,
        );
        watch.stop();
        lastDiagnostic = client.lastDiagnostic;
        plainElapsed = watch.elapsedMilliseconds;
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
        if (client != null && client.lastDiagnostic != null) {
          lastDiagnostic = client.lastDiagnostic;
        }
      }
      if (!gate.cancelled && attached.isEmpty) {
        _note(
          runId,
          RunEventKind.modelRequestFinished,
          _finishedCall(
            callFacts,
            ok: false,
            response: lastDiagnostic?.responseBody,
            elapsedMs: plainElapsed,
            error: '$error',
          ),
          _modelRoute(bodyId),
        );
      }
    }
    agentHttpRequestObserver = null;
    if (gate.cancelled) {
      return;
    }
    if (failure == null && attached.isEmpty) {
      _note(
        runId,
        RunEventKind.modelRequestFinished,
        _finishedCall(
          callFacts,
          ok: true,
          response: lastDiagnostic?.responseBody,
          text: reply ?? '',
          elapsedMs: plainElapsed,
        ),
        _modelRoute(bodyId),
      );
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
    writeLlmReplyToTextKits(
      kitApi: kitApi,
      llmBodyId: bodyId,
      text: failure == null ? (reply ?? '') : failure.toString(),
    );
    _runUse[bodyId]?.wroteOutputAt = DateTime.now();
    _showOutput(bodyId);
    if (failure == null) {
      _appendConversation(
        bodyId: bodyId,
        userText: prompt,
        assistantText: reply ?? '',
      );
      _runUse[bodyId]?.wroteConversationAt = DateTime.now();
    }
    notifyListeners();
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace ?? StackTrace.current);
    }
  }

  void _recordToolEvent(String bodyId, AgentEvent event) {
    if (_gate?.cancelled == true) {
      return;
    }
    final activities = _toolActivities.putIfAbsent(bodyId, () => []);
    final runId = _activeRunId;
    if (event is AgentToolStarted) {
      if (runId != null) {
        final frameId = toolFrameIdForName(
          kitApi.store.document,
          bodyId,
          event.call.name,
        );
        _note(
          runId,
          RunEventKind.toolCallStarted,
          {
            'name': event.call.name,
            'callId': event.call.id,
            'arguments': event.call.argumentsJson,
          },
          frameId == null
              ? routeForKit(kitApi.store.document, bodyId)
              : routeForTool(
                  document: kitApi.store.document,
                  bodyId: bodyId,
                  toolFrameId: frameId,
                ),
        );
      }
      activities.add(
        AgentToolActivity(
          callId: event.call.id,
          name: event.call.name,
          argumentsJson: event.call.argumentsJson,
          state: AgentToolActivityState.running,
        ),
      );
      activeToolFrameId = toolFrameIdForName(
        kitApi.store.document,
        bodyId,
        event.call.name,
      );
      final frameId = activeToolFrameId;
      if (frameId != null) {
        toolPulseFrameId = frameId;
        toolPulseBodyId = bodyId;
        toolPulse++;
        _runUse[bodyId]?.toolCalls[frameId] = DateTime.now();
      }
      _markToolUsed(activeToolFrameId);
      notifyListeners();
    } else if (event is AgentToolFinished) {
      if (runId != null) {
        final frameId = toolFrameIdForName(
          kitApi.store.document,
          bodyId,
          event.call.name,
        );
        _note(
          runId,
          RunEventKind.toolCallFinished,
          {
            'name': event.call.name,
            'callId': event.call.id,
            'ok': event.result.json['ok'] != false,
            'result': event.result.content,
          },
          frameId == null
              ? routeForKit(kitApi.store.document, bodyId)
              : routeForTool(
                  document: kitApi.store.document,
                  bodyId: bodyId,
                  toolFrameId: frameId,
                ),
        );
      }
      final index = activities.lastIndexWhere(
        (activity) => activity.callId == event.call.id,
      );
      if (index >= 0) {
        activities[index] = AgentToolActivity(
          callId: event.call.id,
          name: event.call.name,
          argumentsJson: event.call.argumentsJson,
          state: event.result.json['ok'] == false
              ? AgentToolActivityState.failed
              : AgentToolActivityState.completed,
          result: event.result.content,
        );
      }
      _markToolUsed(activeToolFrameId);
      final frameId = activeToolFrameId ?? toolPulseFrameId;
      if (frameId != null) {
        toolResultFrameId = frameId;
        toolResultBodyId = bodyId;
        toolResultPulse++;
      }
      activeToolFrameId = null;
      notifyListeners();
    }
  }

  void _markToolUsed(String? frameId) {
    if (frameId == null || frameId.isEmpty) {
      return;
    }
    kitApi.updateProps(frameId, {
      toolLastUsedProp: DateTime.now().toUtc().toIso8601String(),
    });
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
        userAt: _runStartedAt,
        assistantAt: DateTime.now(),
      );
    }
  }
}

AgentModel _modelForKit(AgentModel current, String? model) {
  if (current is! OpenAiCompatibleAgentModel) {
    return current;
  }
  final chosen = (model?.trim().isNotEmpty ?? false)
      ? model!.trim()
      : current.model;
  switch (lookupOpenCodeGoModel(chosen)?.surface) {
    case ModelSurface.responses:
      return OpenAiResponsesAgentModel.fromCompatible(current, model: chosen);
    case ModelSurface.messages:
      return OpenAiMessagesAgentModel.fromCompatible(current, model: chosen);
    case ModelSurface.completions:
    case null:
      break;
  }
  if (chosen != current.model) {
    return current.withModel(chosen);
  }
  return current;
}

class _RunCancel {
  var cancelled = false;
}

/// Records one model request around each [AgentModel.complete] in a tool loop.
class _RunLedgerModel implements AgentModel {
  _RunLedgerModel({required this.inner, required this.onRequest});

  final AgentModel inner;
  final void Function(
    bool finished, {
    required bool ok,
    String? response,
    int? elapsedMs,
    String? error,
  })
  onRequest;

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    onRequest(false, ok: true);
    final watch = Stopwatch()..start();
    try {
      final reply = await inner.complete(messages: messages, tools: tools);
      watch.stop();
      onRequest(
        true,
        ok: true,
        response: _modelResponseBody(inner),
        elapsedMs: watch.elapsedMilliseconds,
      );
      return reply;
    } catch (error) {
      watch.stop();
      onRequest(
        true,
        ok: false,
        response: _modelResponseBody(inner),
        elapsedMs: watch.elapsedMilliseconds,
        error: '$error',
      );
      rethrow;
    }
  }
}

Map<String, Object?> _finishedCall(
  Map<String, Object?> facts, {
  required bool ok,
  String? response,
  String? text,
  int? elapsedMs,
  String? error,
}) {
  final usage = tokenUsageFromResponse(response);
  return {
    'ok': ok,
    'model': facts['model'],
    'provider': facts['provider'],
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
    if (usage != null) 'usage': usage,
    if (!ok && error != null && error.isNotEmpty) 'error': error,
    if (response != null && response.isNotEmpty) 'response': response,
    if (text != null) 'text': text,
  };
}

String? _modelResponseBody(AgentModel model) {
  final AgentHttpDiagnostic? diagnostic = switch (model) {
    OpenAiCompatibleAgentModel completions => completions.lastDiagnostic,
    OpenAiResponsesAgentModel responses => responses.lastDiagnostic,
    OpenAiMessagesAgentModel messages => messages.lastDiagnostic,
    _ => null,
  };
  final body = diagnostic?.responseBody ?? '';
  if (body.isEmpty) {
    return null;
  }
  return body;
}
