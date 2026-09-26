import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/agent/llm_run_use.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/agent/run_control.dart';
import 'package:skapie/agent/run_error.dart';
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

enum AgentToolActivityState { running, completed, failed, uncertain }

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
  RunPhase runPhase = RunPhase.ready;
  RunLimits activeLimits = const RunLimits();
  int modelTurnsUsed = 0;
  int toolCallsUsed = 0;
  int outputCharsUsed = 0;
  Duration get runElapsed => _runStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_runStartedAt!);

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
    gate.signal.complete();
    _transition(runId, RunPhase.cancelling);
  }

  void pauseRun() {
    final gate = _gate;
    final runId = _activeRunId;
    if (gate == null || runId == null || gate.cancelled || gate.paused) return;
    gate.paused = true;
    gate.signal.complete();
    _transition(runId, RunPhase.cancelling, reason: 'Pause requested');
  }

  Future<void> flushLedger() => _ledgerWrites;

  /// Check evidence shares the board ledger, but is scoped to its Result body.
  RunRecord beginCheckRun(String resultBodyId, Map<String, Object?> details) {
    final run = ledger.begin(bodyId: resultBodyId, kind: 'check');
    appendCheckEvent(run.id, RunEventKind.checkStarted, details);
    return run;
  }

  void appendCheckEvent(
    String runId,
    RunEventKind kind,
    Map<String, Object?> payload,
  ) => _note(runId, kind, payload);

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

  void _transition(String runId, RunPhase phase, {String? reason}) {
    if (!runPhaseCanMove(runPhase, phase)) {
      throw StateError(
        'Invalid run transition: ${runPhase.name} → ${phase.name}',
      );
    }
    runPhase = phase;
    final previous = ledger
        .runById(runId)
        ?.events
        .reversed
        .where((event) => event.kind == RunEventKind.stateChanged)
        .firstOrNull;
    if (previous?.payload['state'] == phase.name &&
        previous?.payload['modelTurns'] == modelTurnsUsed &&
        previous?.payload['toolCalls'] == toolCallsUsed &&
        previous?.payload['outputChars'] == outputCharsUsed &&
        previous?.payload['reason'] == reason) {
      return;
    }
    _note(runId, RunEventKind.stateChanged, {
      'state': phase.name,
      'reason': ?reason,
      'modelTurns': modelTurnsUsed,
      'toolCalls': toolCallsUsed,
      'outputChars': outputCharsUsed,
    });
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
    if (runningBodyId != null) {
      return;
    }
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
    final gate = _RunCancel();
    _gate = gate;
    final run = ledger.begin(bodyId: bodyId);
    _activeRunId = run.id;
    runPhase = RunPhase.ready;
    _runStartedAt = DateTime.now();
    modelTurnsUsed = 0;
    toolCallsUsed = 0;
    outputCharsUsed = 0;
    activeLimits = runLimitsFor(kitApi.store.document, bodyId);
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
    _note(run.id, RunEventKind.runRequested, {
      'bodyId': bodyId,
      'limits': activeLimits.toJson(),
    }, into);
    _transition(run.id, RunPhase.validating);
    notifyListeners();
    Object? failure;
    StackTrace? failureTrace;
    try {
      final blockers = [
        for (final issue in validateBoard(
          kitApi.store.document,
        ).runBlockers(bodyId, inputSupplied: true))
          if (issue.kind != BoardIssueKind.missingGrant) issue,
      ];
      if (blockers.isNotEmpty) {
        _note(run.id, RunEventKind.graphValidated, {
          'ok': false,
          'reasons': [for (final issue in blockers) issue.message],
        }, into);
        failure = StateError(blockers.first.message);
        _transition(run.id, RunPhase.failed, reason: blockers.first.message);
        updateLlmRunState(
          kitApi: kitApi,
          bodyId: bodyId,
          status: LlmRunStatus.failed,
          error: blockers.first.message,
        );
        _note(run.id, RunEventKind.runFailed, {
          'error': blockers.first.message,
          'category': 'invalidGraph',
        }, into);
        return;
      }
      _note(run.id, RunEventKind.graphValidated, {'ok': true}, into);
      _transition(run.id, RunPhase.assembling);
      updateLlmRunState(
        kitApi: kitApi,
        bodyId: bodyId,
        status: LlmRunStatus.running,
        prompt: prompt,
      );
      await _completeSend(
        prompt: prompt,
        bodyId: bodyId,
        runId: run.id,
        gate: gate,
        limits: activeLimits,
      );
    } catch (error, stack) {
      failure = error;
      failureTrace = stack;
      if (!gate.cancelled && !gate.paused) {
        final category = classifyRunError(error);
        _transition(run.id, RunPhase.failed, reason: runErrorLabel(category));
        if (kitApi.store.document.objectById(bodyId)?.props[llmRunStatusProp] ==
            LlmRunStatus.running.name) {
          updateLlmRunState(
            kitApi: kitApi,
            bodyId: bodyId,
            status: LlmRunStatus.failed,
            error: '$error',
          );
        }
        _note(run.id, RunEventKind.runFailed, {
          'error': '$error',
          'category': category.name,
          if (error is RunLimitReached) 'limit': error.name,
        }, _modelRoute(bodyId));
      }
    } finally {
      if (gate.cancelled) {
        _transition(run.id, RunPhase.interrupted);
        updateLlmRunState(
          kitApi: kitApi,
          bodyId: bodyId,
          status: LlmRunStatus.cancelled,
        );
        _note(run.id, RunEventKind.runInterrupted);
      } else if (gate.paused) {
        _transition(run.id, RunPhase.paused);
        updateLlmRunState(
          kitApi: kitApi,
          bodyId: bodyId,
          status: LlmRunStatus.paused,
        );
        _note(run.id, RunEventKind.runPaused);
      } else if (failure == null) {
        _transition(run.id, RunPhase.completed);
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
      if (gate.paused) return;
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

  Future<String?> _repositoryGrantReason(String bodyId, String name) {
    return repositoryGrantReasonForTool(
      document: kitApi.store.document,
      bodyId: bodyId,
      name: name,
      permission: repositoryPermission,
    );
  }

  Future<void> _completeSend({
    required String prompt,
    required String bodyId,
    required String runId,
    required _RunCancel gate,
    required RunLimits limits,
  }) async {
    final target = kitApi.store.document.objectById(bodyId);
    if (target == null) {
      throw StateError('LLM kit was removed before the request');
    }
    final kitModel = target.props['model']?.toString().trim() ?? '';
    final kitProvider = target.props['provider']?.toString().trim() ?? '';
    final kitSurface = target.props['surface']?.toString().trim() ?? '';
    final model = kitModel.isNotEmpty ? kitModel : runtime.model;
    final provider = kitProvider.isNotEmpty ? kitProvider : runtime.presetId;
    final assembly = assembleContext(
      kitApi: kitApi,
      llmBodyId: bodyId,
      taskInput: prompt,
      repositoryPermission: repositoryPermission,
    );
    final systemText = assembly.instructionText;
    final history = assembly.history;
    final unavailable = <FilteredTool>[
      for (final exclusion in assembly.exclusions)
        if (exclusion.layer == ContextLayer.tools)
          FilteredTool(name: exclusion.sourceKitId, reason: exclusion.reason),
    ];
    final attached = <AgentTool>[];
    for (final tool in assembly.tools) {
      final reason = await _repositoryGrantReason(bodyId, tool.name);
      if (reason == null) {
        attached.add(tool);
      } else {
        unavailable.add(FilteredTool(name: tool.name, reason: reason));
      }
    }
    final callFacts = <String, Object?>{
      'offeredTools': [for (final tool in attached) tool.name],
      'toolSchemaDigest': toolSchemaDigest(attached),
      'filteredTools': [for (final tool in unavailable) tool.toJson()],
      'model': model ?? '',
      'provider': provider,
    };
    if (attached.isEmpty) {
      _note(
        runId,
        RunEventKind.contextAssembled,
        contextProvenancePayload(assembly),
        _modelRoute(bodyId),
      );
      await flushLedger();
    }
    agentHttpRequestObserver = (request) {
      if (!gate.cancelled && !gate.paused) {
        _transition(runId, RunPhase.modelWait);
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
                  required List<AgentMessage> messages,
                  required List<AgentTool> tools,
                }) async {
                  if (!finished) {
                    if (!gate.cancelled && !gate.paused) {
                      _transition(runId, RunPhase.modelWait);
                    }
                    _note(
                      runId,
                      RunEventKind.contextAssembled,
                      contextProvenanceForMessages(messages, tools: tools),
                      _modelRoute(bodyId),
                    );
                    // HTTP models emit their start through the request observer,
                    // which also captures the actual request body.
                    if (turnModel is OpenAiCompatibleAgentModel ||
                        turnModel is OpenAiResponsesAgentModel ||
                        turnModel is OpenAiMessagesAgentModel) {
                      return;
                    }
                    _note(
                      runId,
                      RunEventKind.modelRequestStarted,
                      callFacts,
                      _modelRoute(bodyId),
                    );
                    await flushLedger();
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
                  await flushLedger();
                },
          ),
          kitApi: kitApi,
          tools: attached,
          limits: limits,
          maxToolIterations: limits.effectiveModelTurns,
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
          await turn.sendUser(
            prompt,
            isCancelled: () => gate.cancelled || gate.paused,
            cancellation: gate.signal.future,
            beforeModel: () async {
              final blockers = [
                for (final issue in validateBoard(
                  kitApi.store.document,
                ).runBlockers(bodyId, inputSupplied: true))
                  if (issue.kind != BoardIssueKind.missingGrant) issue,
              ];
              if (blockers.isNotEmpty) {
                throw StateError('Board changed: ${blockers.first.message}');
              }
              final current = llmToolOffer(
                kitApi: kitApi,
                llmBodyId: bodyId,
                repositoryPermission: repositoryPermission,
              );
              final allowed = current.names.toSet();
              if (attached.any((tool) => !allowed.contains(tool.name))) {
                throw StateError('A connected tool lost its grant');
              }
              for (final tool in attached) {
                final reason = await _repositoryGrantReason(bodyId, tool.name);
                if (reason != null) throw StateError(reason);
              }
            },
            toolDenial: (name) async {
              if (!attached.any((tool) => tool.name == name)) {
                return 'Tool is not connected for this turn: $name';
              }
              final current = llmToolOffer(
                kitApi: kitApi,
                llmBodyId: bodyId,
                repositoryPermission: repositoryPermission,
              );
              if (!current.names.contains(name)) {
                return 'Tool grant or connection is no longer valid: $name';
              }
              return _repositoryGrantReason(bodyId, name);
            },
            beforeToolDispatch: flushLedger,
            afterToolResult: flushLedger,
            onPhase: (phase, turns, calls) async {
              modelTurnsUsed = turns;
              toolCallsUsed = calls;
              _transition(runId, phase);
              await flushLedger();
            },
            onOutput: (chars) {
              outputCharsUsed = chars;
              notifyListeners();
            },
          );
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
        modelTurnsUsed = 1;
        _transition(runId, RunPhase.modelWait);
        await flushLedger();
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
        modelTurnsUsed = 1;
        _transition(runId, RunPhase.modelWait);
        await flushLedger();
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
        final request = client.complete(
          userText: prompt,
          systemText: systemText,
          history: history,
        );
        reply = await (limits.elapsed == Duration.zero
            ? request
            : request.timeout(
                limits.elapsed,
                onTimeout: () => throw const RunLimitReached('elapsed time'),
              ));
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
      if (attached.isEmpty) {
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
    if (gate.cancelled || gate.paused) {
      return;
    }
    if (failure == null &&
        limits.outputChars > 0 &&
        (reply?.length ?? 0) > limits.outputChars) {
      failure = const RunLimitReached('output volume');
    }
    if (attached.isEmpty && reply != null) {
      outputCharsUsed = reply.length;
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
            if (event.denial != null) 'denial': event.denial,
          },
          frameId == null || event.denial != null
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
      activeToolFrameId = event.denial == null
          ? toolFrameIdForName(kitApi.store.document, bodyId, event.call.name)
          : null;
      final frameId = activeToolFrameId;
      if (frameId != null) {
        toolPulseFrameId = frameId;
        toolPulseBodyId = bodyId;
        toolPulse++;
        _runUse[bodyId]?.toolCalls[frameId] = DateTime.now();
      }
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
            if (event.denied) 'denied': true,
          },
          frameId == null || event.denied
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
      if (frameId != null && !event.denied) {
        toolResultFrameId = frameId;
        toolResultBodyId = bodyId;
        toolResultPulse++;
      }
      activeToolFrameId = null;
      notifyListeners();
    } else if (event is AgentToolUncertain) {
      if (runId != null) {
        _note(runId, RunEventKind.toolCallUncertain, {
          'name': event.call.name,
          'callId': event.call.id,
          'reason': event.reason,
        });
      }
      final index = activities.lastIndexWhere(
        (activity) => activity.callId == event.call.id,
      );
      if (index >= 0) {
        activities[index] = AgentToolActivity(
          callId: event.call.id,
          name: event.call.name,
          argumentsJson: event.call.argumentsJson,
          state: AgentToolActivityState.uncertain,
          result: event.reason,
        );
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
  var paused = false;
  final signal = Completer<void>();
}

/// Records one model request around each [AgentModel.complete] in a tool loop.
class _RunLedgerModel implements AgentModel {
  _RunLedgerModel({required this.inner, required this.onRequest});

  final AgentModel inner;
  final Future<void> Function(
    bool finished, {
    required bool ok,
    String? response,
    int? elapsedMs,
    String? error,
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
  })
  onRequest;

  @override
  Future<AgentModelReply> complete({
    required List<AgentMessage> messages,
    List<AgentTool> tools = const [],
  }) async {
    await onRequest(false, ok: true, messages: messages, tools: tools);
    final watch = Stopwatch()..start();
    try {
      final reply = await inner.complete(messages: messages, tools: tools);
      watch.stop();
      await onRequest(
        true,
        ok: true,
        response: _modelResponseBody(inner),
        elapsedMs: watch.elapsedMilliseconds,
        messages: messages,
        tools: tools,
      );
      return reply;
    } catch (error) {
      watch.stop();
      await onRequest(
        true,
        ok: false,
        response: _modelResponseBody(inner),
        elapsedMs: watch.elapsedMilliseconds,
        error: '$error',
        messages: messages,
        tools: tools,
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
    'elapsedMs': ?elapsedMs,
    'usage': ?usage,
    if (!ok && error != null && error.isNotEmpty) 'error': error,
    if (response != null && response.isNotEmpty) 'response': response,
    'text': ?text,
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
