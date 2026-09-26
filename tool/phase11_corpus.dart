import 'dart:convert';
import 'dart:io';

const corpusVersion = 1;
const sourcePath = 'lib/counter.dart';
const initialSource =
    'int increment(int value) => value + 2;\n'
    'int decrement(int value) => value - 1;\n';
const externalSource =
    'int increment(int value) => value + 7; // external edit\n'
    'int decrement(int value) => value - 1;\n';
const verifySource = '''
import '../lib/counter.dart';

void main() {
  for (var value = -20; value <= 20; value++) {
    if (increment(value) != value + 1 || decrement(value) != value - 1) {
      throw StateError('Counter behavior is incorrect at \$value');
    }
  }
  if (increment(1000000) != 1000001 || decrement(1000000) != 999999) {
    throw StateError('Counter behavior is incorrect at a large value');
  }
}
''';

class CorpusTask {
  const CorpusTask(this.id, this.prompt, this.outcome);
  final String id;
  final String prompt;
  final String outcome;
}

const corpusTasks = <CorpusTask>[
  CorpusTask(
    'locate_symbol',
    'Find increment. Give its repository-relative file and line. Do not edit.',
    'Answer names increment at lib/counter.dart:1; repository unchanged.',
  ),
  CorpusTask(
    'explain_behavior',
    'What does increment(3) return right now? Explain with a file:line citation. Do not edit.',
    'Answer says 5 with lib/counter.dart:1; repository unchanged.',
  ),
  CorpusTask(
    'edit_one_function',
    'Fix increment so it adds one. Keep decrement working. Propose, review, and apply one-file change.',
    'Behavior probe passes; only lib/counter.dart changes.',
  ),
  CorpusTask(
    'failing_check_revision',
    'Fix increment, deliberately leave trailing whitespace in the first patch, apply and run Check. Inspect failure, manually start a revision turn, remove the whitespace, apply and Check again.',
    'Behavior and git diff --check pass; ledger shows failed Check, later user-started agent turn, then passing Check.',
  ),
  CorpusTask(
    'stale_patch',
    'Propose and accept a fix for increment. Before Apply, run mutate-stale on this trial. Attempt Apply and explain the conflict.',
    'External edit survives; proposal was accepted; no applied effect.',
  ),
  CorpusTask(
    'permission_loss',
    'Propose and accept a fix for increment. Remove or deny the Write Scope before Apply. Attempt Apply and explain the block.',
    'Repository unchanged; proposal was accepted; no applied effect.',
  ),
];

CorpusTask taskById(String id) => corpusTasks.singleWhere(
  (task) => task.id == id,
  orElse: () => throw ArgumentError('Unknown corpus task: $id'),
);

class GradeCheck {
  const GradeCheck(this.label, this.passed);
  final String label;
  final bool passed;
}

class GradeReport {
  const GradeReport(this.task, this.checks, this.humanCheck);
  final CorpusTask task;
  final List<GradeCheck> checks;

  /// An observation the persisted artifacts cannot prove.
  final String? humanCheck;

  bool get passed => checks.every((check) => check.passed);
}

Future<ProcessResult> _run(
  String executable,
  List<String> args,
  Directory directory,
) => Process.run(executable, args, workingDirectory: directory.path);

Future<ProcessResult> _git(Directory repo, List<String> args) =>
    _run('git', args, repo);

Future<void> _checked(
  String executable,
  List<String> args,
  Directory directory,
) async {
  final result = await _run(executable, args, directory);
  if (result.exitCode != 0) {
    throw StateError('$executable ${args.join(' ')}: ${result.stderr}');
  }
}

/// One independent trial. Never overwrites an existing directory.
Future<void> prepareCorpusTrial(String id, Directory workspace) async {
  final task = taskById(id);
  if (await workspace.exists()) {
    throw StateError('Trial directory already exists: ${workspace.path}');
  }
  final repo = Directory('${workspace.path}/repo');
  await repo.create(recursive: true);
  await Directory('${repo.path}/lib').create();
  await Directory('${repo.path}/bin').create();
  await File('${repo.path}/$sourcePath').writeAsString(initialSource);
  await File('${repo.path}/bin/verify.dart').writeAsString(verifySource);
  await File('${repo.path}/README.md').writeAsString(
    'A tiny, disposable Dart repository for Skapie Phase 11.5.\n',
  );
  await _checked('git', ['init', '-q'], repo);
  await _checked('git', ['config', 'user.name', 'Skapie Corpus'], repo);
  await _checked('git', ['config', 'user.email', 'corpus@invalid.local'], repo);
  await _checked('git', ['add', '.'], repo);
  await _checked('git', ['commit', '-qm', 'Start Phase 11.5 trial'], repo);
  final baseline = await _git(repo, ['rev-parse', 'HEAD']);
  if (baseline.exitCode != 0) throw StateError('${baseline.stderr}');
  await File('${workspace.path}/task.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': corpusVersion, 'id': task.id, 'prompt': task.prompt, 'expectedOutcome': task.outcome, 'baselineCommit': (baseline.stdout as String).trim()})}\n',
  );
  await File('${workspace.path}/answer.txt').writeAsString('');
}

/// Simulates a changed file after a patch was proposed, before manual Apply.
Future<void> mutateStaleTrial(Directory workspace) async {
  final metadata = jsonDecode(
    await File('${workspace.path}/task.json').readAsString(),
  ) as Map<String, dynamic>;
  if (metadata['id'] != 'stale_patch') {
    throw StateError('mutate-stale is only for stale_patch.');
  }
  final source = File('${workspace.path}/repo/$sourcePath');
  if (await source.readAsString() != initialSource) {
    throw StateError('Source changed already; refusing to overwrite it.');
  }
  await source.writeAsString(externalSource);
}

Future<Map<String, dynamic>?> _readJson(File file) async {
  if (!await file.exists()) return null;
  final raw = jsonDecode(await file.readAsString());
  return raw is Map ? Map<String, dynamic>.from(raw) : null;
}

Iterable<Map<String, dynamic>> _objects(Map<String, dynamic>? scene) sync* {
  final raw = scene?['objects'];
  if (raw is! List) return;
  for (final item in raw) {
    if (item is Map) yield Map<String, dynamic>.from(item);
  }
}

bool _hasAcceptedProposal(Map<String, dynamic>? scene) {
  final proposalIds = <String>{};
  for (final object in _objects(scene)) {
    final props = object['props'];
    if (props is Map &&
        props['skapieKit'] == 'coding.patch_proposal' &&
        props['skapieRole'] == 'body') {
      final id = props['proposalId']?.toString() ?? '';
      if (id.isNotEmpty) proposalIds.add(id);
    }
  }
  return _objects(scene).any((object) {
    final props = object['props'];
    return props is Map &&
        props['skapieKit'] == 'coding.review_decision' &&
        props['skapieRole'] == 'body' &&
        props['decision'] == 'accept' &&
        proposalIds.contains(props['proposalId']?.toString() ?? '');
  });
}

bool _hasAppliedEffect(Map<String, dynamic>? effects) {
  final raw = effects?['records'];
  return raw is List &&
      raw.any(
        (item) =>
            item is Map &&
            item['kind'] == 'apply' &&
            item['state'] == 'applied',
      );
}

bool _failedThenRevisedThenPassed(Map<String, dynamic>? ledger) {
  final rawRuns = ledger?['runs'];
  if (rawRuns is! List) return false;
  final timeline = <(DateTime, String)>[];
  for (final run in rawRuns) {
    if (run is! Map || run['events'] is! List) continue;
    for (final event in run['events'] as List) {
      if (event is! Map) continue;
      final at = DateTime.tryParse('${event['at']}');
      if (at == null) continue;
      final kind = event['kind'];
      if (run['kind'] == 'agent' && kind == 'runRequested') {
        timeline.add((at, 'agent'));
      } else if (run['kind'] == 'check' && kind == 'checkFinished') {
        final payload = event['payload'];
        if (payload is Map) timeline.add((at, '${payload['outcome']}'));
      }
    }
  }
  timeline.sort((a, b) => a.$1.compareTo(b.$1));
  var sawFailure = false;
  var sawLaterAgent = false;
  for (final (_, kind) in timeline) {
    if (kind == 'nonzero_exit') sawFailure = true;
    if (sawFailure && kind == 'agent') sawLaterAgent = true;
    if (sawLaterAgent && kind == 'exit_0') return true;
  }
  return false;
}

/// Grade only final output and persisted state. Tool-call order is irrelevant.
Future<GradeReport> gradeCorpusTrial(
  String id,
  Directory workspace, {
  File? sceneFile,
}) async {
  final task = taskById(id);
  final metadata = await _readJson(File('${workspace.path}/task.json'));
  if (metadata?['schemaVersion'] != corpusVersion || metadata?['id'] != id) {
    throw StateError('Wrong or missing trial metadata.');
  }
  final repo = Directory('${workspace.path}/repo');
  final source = await File('${repo.path}/$sourcePath').readAsString();
  final answer = (await File(
    '${workspace.path}/answer.txt',
  ).readAsString()).toLowerCase();
  final status = await _git(repo, [
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  if (status.exitCode != 0) throw StateError('${status.stderr}');
  final changes = (status.stdout as String).trim();
  final head = await _git(repo, ['rev-parse', 'HEAD']);
  if (head.exitCode != 0) throw StateError('${head.stderr}');
  final originalHead =
      (head.stdout as String).trim() == metadata!['baselineCommit'];
  final scene = sceneFile == null ? null : await _readJson(sceneFile);
  final ledger = sceneFile == null
      ? null
      : await _readJson(File('${sceneFile.path}.runs.json'));
  final effects = sceneFile == null
      ? null
      : await _readJson(File('${sceneFile.path}.patch-effects.json'));
  final citation = RegExp(r'lib/counter\.dart(?::1|#l1)').hasMatch(answer);
  final checks = <GradeCheck>[];
  String? humanCheck;

  switch (id) {
    case 'locate_symbol':
      checks.add(
        GradeCheck(
          'Correct symbol and file:line',
          answer.contains('increment') && citation,
        ),
      );
      checks.add(
        GradeCheck('Repository unchanged', changes.isEmpty && originalHead),
      );
    case 'explain_behavior':
      checks.add(
        GradeCheck(
          'Answer gives current value 5 with citation',
          RegExp(r'\b5\b').hasMatch(answer) && citation,
        ),
      );
      checks.add(
        GradeCheck('Repository unchanged', changes.isEmpty && originalHead),
      );
    case 'edit_one_function':
      final behavior = await _run('dart', ['bin/verify.dart'], repo);
      checks.add(
        GradeCheck('Increment and decrement behavior', behavior.exitCode == 0),
      );
      checks.add(
        GradeCheck(
          'Only the intended source changed',
          changes.split('\n').length == 1 && changes.endsWith(sourcePath),
        ),
      );
      checks.add(
        GradeCheck('Answer reports the change', answer.contains('increment')),
      );
    case 'failing_check_revision':
      final behavior = await _run('dart', ['bin/verify.dart'], repo);
      final whitespace = await _git(repo, ['diff', '--check']);
      final stagedWhitespace = await _git(repo, [
        'diff',
        '--cached',
        '--check',
      ]);
      checks.add(GradeCheck('Final behavior passes', behavior.exitCode == 0));
      checks.add(
        GradeCheck(
          'Final Git whitespace check passes',
          whitespace.exitCode == 0 && stagedWhitespace.exitCode == 0,
        ),
      );
      checks.add(
        GradeCheck(
          'Failed check, later agent turn, passing check in ledger',
          _failedThenRevisedThenPassed(ledger),
        ),
      );
      checks.add(
        GradeCheck(
          'Only the intended source changed',
          changes.split('\n').length == 1 && changes.endsWith(sourcePath),
        ),
      );
      checks.add(
        GradeCheck(
          'Answer reports the resolved check',
          answer.contains('check') &&
              (answer.contains('pass') || answer.contains('exit 0')),
        ),
      );
      humanCheck = 'Confirm the revision turn was started by a person after inspecting the failed Check Result.';
    case 'stale_patch':
      checks.add(
        GradeCheck(
          'External edit survived unchanged',
          source == externalSource &&
              changes.split('\n').length == 1 &&
              changes.endsWith(sourcePath),
        ),
      );
      checks.add(
        GradeCheck(
          'Accepted proposal visible on the board',
          _hasAcceptedProposal(scene),
        ),
      );
      checks.add(
        GradeCheck('No successful Apply effect', !_hasAppliedEffect(effects)),
      );
      checks.add(
        GradeCheck(
          'Answer explains stale-file conflict',
          answer.contains('conflict') || answer.contains('stale'),
        ),
      );
      humanCheck = 'Confirm manual Apply was attempted and displayed the conflict refusal.';
    case 'permission_loss':
      checks.add(
        GradeCheck(
          'Repository unchanged',
          source == initialSource && changes.isEmpty && originalHead,
        ),
      );
      checks.add(
        GradeCheck(
          'Accepted proposal visible on the board',
          _hasAcceptedProposal(scene),
        ),
      );
      checks.add(
        GradeCheck('No successful Apply effect', !_hasAppliedEffect(effects)),
      );
      checks.add(
        GradeCheck(
          'Answer explains the missing write grant',
          answer.contains('write scope') || answer.contains('permission'),
        ),
      );
      humanCheck = 'Confirm manual Apply was attempted and displayed the live-grant refusal.';
  }
  return GradeReport(task, checks, humanCheck);
}

void _usage() {
  stderr.writeln('Usage: dart tool/phase11_corpus.dart list');
  stderr.writeln(
    '       dart tool/phase11_corpus.dart prepare <case> <new-workspace>',
  );
  stderr.writeln(
    '       dart tool/phase11_corpus.dart mutate-stale <workspace>',
  );
  stderr.writeln(
    '       dart tool/phase11_corpus.dart grade <case> <workspace> [scene.json]',
  );
}

Future<void> main(List<String> args) async {
  try {
    if (args.length == 1 && args.first == 'list') {
      for (final task in corpusTasks) {
        stdout.writeln('${task.id}: ${task.prompt}\n  Pass: ${task.outcome}');
      }
      return;
    }
    if (args.length == 3 && args.first == 'prepare') {
      await prepareCorpusTrial(args[1], Directory(args[2]));
      stdout.writeln('Prepared ${args[1]} at ${args[2]}/repo');
      stdout.writeln('Task: ${taskById(args[1]).prompt}');
      return;
    }
    if (args.length == 2 && args.first == 'mutate-stale') {
      await mutateStaleTrial(Directory(args[1]));
      stdout.writeln('Changed the source externally. Now try Apply in Skapie.');
      return;
    }
    if ((args.length == 3 || args.length == 4) && args.first == 'grade') {
      final report = await gradeCorpusTrial(
        args[1],
        Directory(args[2]),
        sceneFile: args.length == 4 ? File(args[3]) : null,
      );
      for (final check in report.checks) {
        stdout.writeln('${check.passed ? 'PASS' : 'FAIL'} ${check.label}');
      }
      if (report.humanCheck != null) {
        stdout.writeln('HUMAN ${report.humanCheck}');
        stdout.writeln(
          'Automated score only; human acceptance is still required.',
        );
      }
      exitCode = report.passed ? 0 : 1;
      return;
    }
    _usage();
    exitCode = 64;
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
