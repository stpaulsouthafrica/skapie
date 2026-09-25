import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/check/check_board.dart';
import 'package:skapie/tools/check/check_redaction.dart';
import 'package:skapie/tools/patch/write_permission.dart';

class _WritePermission implements PatchWritePermission {
  const _WritePermission(this.allowed);
  final bool allowed;
  @override
  Future<bool> canWrite(String path) async => allowed;
  @override
  Future<String?> chooseDirectory() async => null;
  @override
  Future<String?> exportProposal({
    required String name,
    required String text,
  }) async => null;
}

class _CheckRunner implements CheckProcessRunner {
  _CheckRunner(this.reply, {this.chunks = const []});
  final Future<Map<String, Object?>> Function() reply;
  final List<CheckProcessChunk> chunks;
  int runs = 0;
  int cancels = 0;
  @override
  Future<Map<String, Object?>> runGitDiffCheck(
    String root, {
    void Function(CheckProcessChunk)? onChunk,
  }) {
    runs++;
    for (final chunk in chunks) {
      onChunk?.call(chunk);
    }
    return reply();
  }

  @override
  Future<bool> cancel() async {
    cancels++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late KitApi kitApi;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('skapie-check-');
    kitApi = createAppKitApi(store: SceneStore());
  });
  tearDown(() async => scratch.delete(recursive: true));

  List<String> place(String id) => kitApi.instantiate(id, origin: Offset.zero);

  void connect(
    KitPortKind fromKind,
    String fromId,
    KitPortKind toKind,
    String toId,
  ) {
    final ports = kitPorts(kitApi.store.document);
    connectKitPorts(
      kitApi: kitApi,
      from: ports.singleWhere(
        (port) => port.frameId == fromId && port.kind == fromKind,
      ),
      to: ports.singleWhere(
        (port) => port.frameId == toId && port.kind == toKind,
      ),
    );
  }

  test('three kits register and only compatible typed cables connect', () {
    expect(kitApi.getKit(codingCheckSpecKitId), isNotNull);
    expect(kitApi.getKit(codingRunCheckKitId), isNotNull);
    expect(kitApi.getKit(codingCheckResultKitId), isNotNull);
    expect(
      kitPortRefusal(KitPortKind.checkSpecOut, KitPortKind.runCheckSpec),
      isNull,
    );
    expect(
      kitPortRefusal(KitPortKind.writeScopeOut, KitPortKind.runCheckWrite),
      isNull,
    );
    expect(
      kitPortRefusal(KitPortKind.runCheckResult, KitPortKind.checkResultIn),
      isNull,
    );
    expect(
      kitPortRefusal(KitPortKind.checkResultOut, KitPortKind.llmContext),
      isNull,
    );
    expect(
      kitPortRefusal(KitPortKind.toolOut, KitPortKind.runCheckSpec),
      isNotNull,
    );
    expect(
      kitPortRefusal(KitPortKind.checkResultOut, KitPortKind.llmInput),
      isNotNull,
    );
  });

  test('cabling and a model-like shell value never start a process', () async {
    final spec = place(codingCheckSpecKitId);
    final run = place(codingRunCheckKitId);
    final result = place(codingCheckResultKitId);
    final scope = place(codingWriteScopeKitId);
    final runner = _CheckRunner(() async => {'outcome': 'exit_0'});
    connect(
      KitPortKind.checkSpecOut,
      spec.first,
      KitPortKind.runCheckSpec,
      run.first,
    );
    connect(
      KitPortKind.runCheckResult,
      run.first,
      KitPortKind.checkResultIn,
      result.first,
    );
    connect(
      KitPortKind.writeScopeOut,
      scope.first,
      KitPortKind.runCheckWrite,
      run.first,
    );
    kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
    expect(runner.runs, 0);
    expect(checkGate(kitApi.store.document, run.first).ready, isFalse);
    kitApi.updateProps(spec.first, {checkPresetProp: 'sh -c arbitrary text'});
    final refused = await invokeRunCheck(
      kitApi: kitApi,
      runFrameId: run.first,
      permission: const _WritePermission(true),
      runner: runner,
    );
    expect(refused.started, isFalse);
    expect(runner.runs, 0);
    expect(
      checkResultBody(
        kitApi.store.document,
        result.first,
      )!.props['checkOutcome'],
      '',
    );
  });

  test('Run requires the separate live write grant and Result cable', () async {
    final spec = place(codingCheckSpecKitId);
    final run = place(codingRunCheckKitId);
    final scope = place(codingWriteScopeKitId);
    final runner = _CheckRunner(() async => {'outcome': 'exit_0'});
    kitApi.updateProps(spec.first, {checkPresetProp: gitDiffCheckPreset});
    kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
    connect(
      KitPortKind.checkSpecOut,
      spec.first,
      KitPortKind.runCheckSpec,
      run.first,
    );
    connect(
      KitPortKind.writeScopeOut,
      scope.first,
      KitPortKind.runCheckWrite,
      run.first,
    );
    expect(
      checkGate(kitApi.store.document, run.first).reason,
      contains('Check Result'),
    );
    final result = place(codingCheckResultKitId);
    connect(
      KitPortKind.runCheckResult,
      run.first,
      KitPortKind.checkResultIn,
      result.first,
    );
    final denied = await invokeRunCheck(
      kitApi: kitApi,
      runFrameId: run.first,
      permission: const _WritePermission(false),
      runner: runner,
    );
    expect(denied.started, isFalse);
    expect(runner.runs, 0);
  });

  test('explicit Run records bounded outcome and only a summary reaches LLM Context', () async {
    final spec = place(codingCheckSpecKitId);
    final run = place(codingRunCheckKitId);
    final result = place(codingCheckResultKitId);
    final scope = place(codingWriteScopeKitId);
    final llm = place(harnessLlmKitId);
    kitApi.updateProps(spec.first, {checkPresetProp: gitDiffCheckPreset});
    kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
    connect(
      KitPortKind.checkSpecOut,
      spec.first,
      KitPortKind.runCheckSpec,
      run.first,
    );
    connect(
      KitPortKind.writeScopeOut,
      scope.first,
      KitPortKind.runCheckWrite,
      run.first,
    );
    connect(
      KitPortKind.runCheckResult,
      run.first,
      KitPortKind.checkResultIn,
      result.first,
    );
    connect(
      KitPortKind.checkResultOut,
      result.first,
      KitPortKind.llmContext,
      llm.first,
    );
    final runner = _CheckRunner(
      () async => {
        'outcome': 'exit_0',
        'exitCode': 0,
        'beforeGit': ' M file.txt\n',
        'afterGit': ' M file.txt\n',
        'gitStateKnown': true,
        'stdout': 'private raw output',
      },
    );
    expect(llmContextText(kitApi.store.document, llm.last), isEmpty);
    final attempted = await invokeRunCheck(
      kitApi: kitApi,
      runFrameId: run.first,
      permission: const _WritePermission(true),
      runner: runner,
    );
    expect(attempted.started, isTrue);
    expect(attempted.outcome, 'exit_0');
    expect(runner.runs, 1);
    final body = checkResultBody(kitApi.store.document, result.first)!;
    expect(body.props['checkOutcome'], 'exit_0');
    expect(body.props['checkBeforeGit'], body.props['checkAfterGit']);
    expect(
      llmContextText(kitApi.store.document, llm.last),
      contains('Exited 0'),
    );
    expect(
      llmContextText(kitApi.store.document, llm.last),
      isNot(contains('private raw output')),
    );
  });

  test('split secrets, output chunks, metadata and truncation stay redacted in the board ledger', () async {
    final spec = place(codingCheckSpecKitId);
    final run = place(codingRunCheckKitId);
    final result = place(codingCheckResultKitId);
    final scope = place(codingWriteScopeKitId);
    final llm = place(harnessLlmKitId);
    kitApi.updateProps(spec.first, {checkPresetProp: gitDiffCheckPreset});
    kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
    connect(
      KitPortKind.checkSpecOut,
      spec.first,
      KitPortKind.runCheckSpec,
      run.first,
    );
    connect(
      KitPortKind.writeScopeOut,
      scope.first,
      KitPortKind.runCheckWrite,
      run.first,
    );
    connect(
      KitPortKind.runCheckResult,
      run.first,
      KitPortKind.checkResultIn,
      result.first,
    );
    connect(
      KitPortKind.checkResultOut,
      result.first,
      KitPortKind.llmContext,
      llm.first,
    );
    const secret = 'sk-test-secret-1234567890';
    final runner = _CheckRunner(
      () async => {
        'outcome': 'exit_0',
        'argv': ['/installed/git', 'diff', '--check'],
        'cwd': scratch.path,
        'environmentKeys': ['PATH', 'HOME'],
        'startedAt': '2026-09-25T12:00:00Z',
        'finishedAt': '2026-09-25T12:00:01Z',
        'exitCode': 0,
        'truncated': true,
        'beforeGit': ' M file.txt\n',
        'afterGit': ' M file.txt\n',
        'gitStateKnown': true,
        'stdout': 'do not duplicate $secret',
      },
      chunks: const [
        CheckProcessChunk(
          phase: 'check',
          stream: 'stdout',
          text: 'token=sk-test-',
          at: '12:00:00',
        ),
        CheckProcessChunk(
          phase: 'check',
          stream: 'stdout',
          text: 'secret-1234567890\nordinary line\n',
          at: '12:00:01',
        ),
        CheckProcessChunk(
          phase: 'check',
          stream: 'stderr',
          text: 'Authorization: Bearer abc123456789\n',
          at: '12:00:01',
        ),
      ],
    );
    final ledger = RunLedger();
    final attempt = await invokeRunCheck(
      kitApi: kitApi,
      runFrameId: run.first,
      permission: const _WritePermission(true),
      runner: runner,
      beginEvidence: (id, details) {
        final record = ledger.begin(bodyId: id, kind: 'check');
        ledger.append(record.id, RunEventKind.checkStarted, details);
        return record;
      },
      appendEvidence: (id, kind, payload) => ledger.append(id, kind, payload),
    );
    expect(attempt.outcome, 'exit_0');
    final record = ledger.runs.single;
    expect(record.kind, 'check');
    expect(
      record.events.where((event) => event.kind == RunEventKind.checkOutput),
      hasLength(2),
    );
    final finished = record.events.last;
    expect(finished.kind, RunEventKind.checkFinished);
    expect(finished.payload['argv'], ['/installed/git', 'diff', '--check']);
    expect(finished.payload['environmentKeys'], ['PATH', 'HOME']);
    expect(finished.payload['exitCode'], 0);
    expect(finished.payload['truncated'], true);
    expect(finished.payload['gitStateKnown'], true);
    final file = RunLedgerFile(File('${scratch.path}/board.runs.json'));
    await file.write(ledger);
    final saved = await file.file.readAsString();
    expect(saved, contains('[REDACTED]'));
    expect(saved, isNot(contains(secret)));
    expect(saved, isNot(contains('abc123456789')));
    final reopened = RunLedger();
    await file.loadInto(reopened);
    expect(reopened.runs.single.events.last.payload['outcome'], 'exit_0');
    expect(jsonEncode(kitApi.store.document.toJson()), isNot(contains(secret)));
    expect(
      llmContextText(kitApi.store.document, llm.last),
      isNot(contains('ordinary line')),
    );
  });

  test('oversized secret line is withheld rather than partially streamed', () {
    final redactor = CheckLineRedactor();
    expect(redactor.add('check:stdout', 'x' * 4100), isEmpty);
    expect(redactor.add('check:stdout', 'sk-test-secret-1234567890\n'), [
      '[output line redacted: too long]\n',
    ]);
    expect(redactor.finish(), isEmpty);
    expect(
      redactCheckText('AWS_SECRET_ACCESS_KEY=fake-sensitive-value'),
      'AWS_SECRET_ACCESS_KEY=[REDACTED]',
    );
  });

  test('all five outcome categories remain distinct and never imply task completion', () async {
    final spec = place(codingCheckSpecKitId);
    final run = place(codingRunCheckKitId);
    final result = place(codingCheckResultKitId);
    final scope = place(codingWriteScopeKitId);
    kitApi.updateProps(spec.first, {checkPresetProp: gitDiffCheckPreset});
    kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
    connect(
      KitPortKind.checkSpecOut,
      spec.first,
      KitPortKind.runCheckSpec,
      run.first,
    );
    connect(
      KitPortKind.writeScopeOut,
      scope.first,
      KitPortKind.runCheckWrite,
      run.first,
    );
    connect(
      KitPortKind.runCheckResult,
      run.first,
      KitPortKind.checkResultIn,
      result.first,
    );
    final cases = <(String, String, String)>[
      ('exit_0', 'Exited 0', ''),
      ('nonzero_exit', 'Nonzero exit', ''),
      ('timeout', 'Timed out', ''),
      ('cancelled', 'Cancelled', ''),
      (
        'infrastructure_error',
        'Infrastructure error',
        'Could not start installed Git',
      ),
    ];
    final ledger = RunLedger();
    for (final (category, label, error) in cases) {
      final attempt = await invokeRunCheck(
        kitApi: kitApi,
        runFrameId: run.first,
        permission: const _WritePermission(true),
        runner: _CheckRunner(
          () async => {
            'outcome': category,
            'error': error,
            'exitCode': category == 'exit_0' ? 0 : 1,
            'gitStateKnown': false,
          },
        ),
        beginEvidence: (id, details) {
          final record = ledger.begin(bodyId: id, kind: 'check');
          ledger.append(record.id, RunEventKind.checkStarted, details);
          return record;
        },
        appendEvidence: (id, kind, payload) => ledger.append(id, kind, payload),
      );
      expect(attempt.outcome, category);
      expect(attempt.message, contains(label));
      expect(attempt.message.toLowerCase(), isNot(contains('task complete')));
      expect(ledger.runs.last.events.last.payload['outcome'], category);
      expect(
        ledger.runs.last.events.last.payload['cancelled'],
        category == 'cancelled',
      );
    }
    expect(ledger.runs, hasLength(5));
    expect(
      checkResultBody(
        kitApi.store.document,
        result.first,
      )!.props['checkOutcome'],
      'infrastructure_error',
    );
  });

  test(
    'cancel request settles as cancelled without claiming success',
    () async {
      final spec = place(codingCheckSpecKitId);
      final run = place(codingRunCheckKitId);
      final result = place(codingCheckResultKitId);
      final scope = place(codingWriteScopeKitId);
      kitApi.updateProps(spec.first, {checkPresetProp: gitDiffCheckPreset});
      kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
      connect(
        KitPortKind.checkSpecOut,
        spec.first,
        KitPortKind.runCheckSpec,
        run.first,
      );
      connect(
        KitPortKind.writeScopeOut,
        scope.first,
        KitPortKind.runCheckWrite,
        run.first,
      );
      connect(
        KitPortKind.runCheckResult,
        run.first,
        KitPortKind.checkResultIn,
        result.first,
      );
      final completion = Completer<Map<String, Object?>>();
      final runner = _CheckRunner(() => completion.future);
      final pending = invokeRunCheck(
        kitApi: kitApi,
        runFrameId: run.first,
        permission: const _WritePermission(true),
        runner: runner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(await runner.cancel(), isTrue);
      completion.complete({'outcome': 'cancelled', 'gitStateKnown': false});
      final attempted = await pending;
      expect(attempted.outcome, 'cancelled');
      expect(runner.cancels, 1);
      expect(
        checkResultBody(kitApi.store.document, result.first)!.props['content'],
        contains('Cancelled'),
      );
    },
  );

  testWidgets(
    'Inspector shows the trusted preset and a deliberate Run confirmation',
    (tester) async {
      final spec = place(codingCheckSpecKitId);
      final run = place(codingRunCheckKitId);
      final result = place(codingCheckResultKitId);
      final scope = place(codingWriteScopeKitId);
      kitApi.updateProps(scope.first, {writeScopePathProp: scratch.path});
      connect(
        KitPortKind.checkSpecOut,
        spec.first,
        KitPortKind.runCheckSpec,
        run.first,
      );
      connect(
        KitPortKind.writeScopeOut,
        scope.first,
        KitPortKind.runCheckWrite,
        run.first,
      );
      connect(
        KitPortKind.runCheckResult,
        run.first,
        KitPortKind.checkResultIn,
        result.first,
      );
      final runner = _CheckRunner(() async => {'outcome': 'exit_0'});
      final selection = SelectionController()..select(spec.first);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectorPanel(
              store: kitApi.store,
              selection: selection,
              kitApi: kitApi,
              writePermission: const _WritePermission(true),
              checkRunner: runner,
            ),
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const Key('choose-git-diff-check')),
      );
      await tester.tap(find.byKey(const Key('choose-git-diff-check')));
      await tester.pump();
      expect(
        kitApi.store.document.objectById(spec.first)!.props[checkPresetProp],
        gitDiffCheckPreset,
      );
      selection.select(run.first);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('run-check-action')));
      await tester.tap(find.byKey(const Key('run-check-action')));
      await tester.pump();
      expect(find.textContaining('Network access is allowed'), findsOneWidget);
      expect(find.textContaining('diff --check'), findsWidgets);
      expect(runner.runs, 0);
      await tester.tap(find.text('Cancel').last);
      await tester.pump();
      expect(runner.runs, 0);
      selection.dispose();
    },
  );

  testWidgets('Check Result opens its board ledger with redacted output', (
    tester,
  ) async {
    final result = place(codingCheckResultKitId);
    final body = checkResultBody(kitApi.store.document, result.first)!;
    kitApi.updateProps(body.id, {
      'content': 'Git diff --check · Nonzero exit · Git status unchanged',
      'checkOutcome': 'nonzero_exit',
      'checkGitStateKnown': true,
      'checkGitChanged': false,
    });
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );
    final record = controller.beginCheckRun(body.id, {'cwd': scratch.path});
    controller.appendCheckEvent(record.id, RunEventKind.checkOutput, {
      'phase': 'check',
      'stream': 'stderr',
      'text': 'token=[REDACTED]\n',
    });
    controller.appendCheckEvent(record.id, RunEventKind.checkFinished, {
      'outcome': 'nonzero_exit',
      'exitCode': 2,
      'truncated': false,
    });
    final selection = SelectionController()..select(result.first);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(
            store: kitApi.store,
            selection: selection,
            kitApi: kitApi,
            controller: controller,
          ),
        ),
      ),
    );
    expect(find.textContaining('Latest redacted output'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('open-check-ledger')));
    await tester.tap(find.byKey(const Key('open-check-ledger')));
    await tester.pumpAndSettle();
    expect(find.text('Check run ledger'), findsOneWidget);
    await tester.tap(find.byKey(Key('check-ledger-${record.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('token=[REDACTED]'), findsWidgets);
    expect(find.textContaining('exitCode: 2'), findsOneWidget);
    selection.dispose();
    controller.dispose();
  });
}
