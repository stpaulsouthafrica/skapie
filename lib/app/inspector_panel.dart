import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/app/full_screen_text_editor.dart';
import 'package:skapie/app/patch_diff_viewer.dart';
import 'package:skapie/app/connection_inspector.dart';
import 'package:skapie/app/llm_kit_input.dart';
import 'package:skapie/app/llm_request_information.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/tools/patch/patch_effect_log.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/check/check_board.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

/// Clock time for a tool's last invocation. A previous day includes the date.
String formatToolLastUse(String raw, {DateTime? now}) {
  final time = DateTime.tryParse(raw)?.toLocal();
  if (time == null) {
    return raw;
  }
  final clock =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  final today = now ?? DateTime.now();
  if (time.year == today.year &&
      time.month == today.month &&
      time.day == today.day) {
    return clock;
  }
  return '${time.month}/${time.day} $clock';
}

/// Thin inspector. Edits go through [KitApi] → [SceneStore.apply] only.
class InspectorPanel extends StatefulWidget {
  InspectorPanel({
    super.key,
    required this.store,
    required this.selection,
    KitApi? kitApi,
    this.lastLlmBodyId,
    this.controller,
    this.onCutCable,
    this.writePermission = const SystemPatchWritePermission(),
    this.effectLog,
    this.checkRunner = const SystemCheckProcessRunner(),
    this.checkDirectoryExists,
  }) : kitApi =
           kitApi ?? KitApi(store: store, registry: createBuiltinRegistry());

  final SceneStore store;
  final SelectionController selection;
  final KitApi kitApi;
  final String? lastLlmBodyId;
  final AgentController? controller;
  final PatchWritePermission writePermission;
  final PatchEffectLog? effectLog;
  final CheckProcessRunner checkRunner;
  final Future<bool> Function(String path)? checkDirectoryExists;

  /// When set, Cut cable plays the board retraction instead of vanishing.
  final ValueChanged<SceneCable>? onCutCable;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  Timer? _debounce;
  String? _boundId;
  final _x = TextEditingController();
  final _y = TextEditingController();
  final _content = TextEditingController();
  final _contentFocus = FocusNode();
  final _fontSize = TextEditingController();
  final _color = TextEditingController();
  final _fill = TextEditingController();
  final _label = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _description = TextEditingController();
  final _descriptionFocus = FocusNode();
  RepositoryPermission get _repositoryPermission =>
      widget.controller?.repositoryPermission ??
      const SystemRepositoryPermission();
  String? _repositoryError;
  String? _reviewError;
  String? _effectMessage;
  bool _effectBusy = false;
  bool _checkBusy = false;
  String? _checkMessage;
  late PatchEffectLog _effects;

  Future<void> _loadEffects() async {
    try {
      await _effects.load();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(
          () => _effectMessage = 'Could not read effect history: $error',
        );
      }
    }
  }

  Future<void> _chooseWriteScope(SceneObject frame) async {
    try {
      final path = await widget.writePermission.chooseDirectory();
      if (path == null || path.isEmpty) return;
      widget.kitApi.updateProps(frame.id, {writeScopePathProp: path});
      if (mounted) setState(() => _effectMessage = null);
    } catch (error) {
      if (mounted) {
        setState(() => _effectMessage = 'Write grant failed: $error');
      }
    }
  }

  Future<void> _exportProposal(SceneObject body) async {
    final path = body.props['path']?.toString() ?? 'patch';
    try {
      final exported = await widget.writePermission.exportProposal(
        name: '${path.split('/').last}.proposal.json',
        text:
            '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'proposalId': body.props[proposalIdProp], 'fingerprint': body.props[proposalFingerprintProp], 'repositoryPath': body.props['repositoryPath'], 'path': body.props['path'], 'baseFingerprint': body.props['baseFingerprint'], 'oldText': body.props['oldText'], 'newText': body.props['newText'], 'diff': body.props['diff']})}\n',
      );
      if (mounted && exported != null) {
        setState(() => _effectMessage = 'Exported proposal to $exported');
      }
    } catch (error) {
      if (mounted) setState(() => _effectMessage = 'Export failed: $error');
    }
  }

  Future<void> _applyPatch(SceneObject frame) async {
    final review = connectedReviewFrame(widget.store.document, frame.id);
    final proposal = review == null
        ? null
        : connectedProposalFrame(widget.store.document, review.id);
    final body = proposal == null
        ? null
        : patchProposalBody(widget.store.document, proposal.id);
    final path = body?.props['path']?.toString() ?? 'this file';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply accepted patch?'),
        content: Text(
          'Skapie will verify and write $path. This is a repository effect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply patch'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _effectBusy = true;
      _effectMessage = 'Verifying file…';
    });
    final result = await invokeApplyPatch(
      kitApi: widget.kitApi,
      applyFrameId: frame.id,
      permission: widget.writePermission,
      effects: _effects,
    );
    if (mounted) {
      setState(() {
        _effectBusy = false;
        _effectMessage = result.reason;
      });
    }
  }

  Future<void> _revertPatch(String effectId, String writeScopePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revert this file effect?'),
        content: const Text(
          'Skapie will restore the saved preimage only if the file still matches the applied result.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revert file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _effectBusy = true;
      _effectMessage = 'Checking file before Revert…';
    });
    final result = await invokeRevertPatch(
      effects: _effects,
      effectId: effectId,
      permission: widget.writePermission,
      writeScopePath: writeScopePath,
    );
    if (mounted) {
      setState(() {
        _effectBusy = false;
        _effectMessage = result.reason;
      });
    }
  }

  void _review(String decision, SceneObject frame) {
    final recorded = recordReviewDecision(
      kitApi: widget.kitApi,
      reviewFrameId: frame.id,
      decision: decision,
    );
    setState(() {
      _reviewError = recorded ? null : 'This decision is settled. Reconsider it explicitly or review a new proposal.';
    });
  }

  Future<void> _reconsider(SceneObject frame) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reconsider this decision?'),
        content: const Text(
          'This clears the recorded decision. You will need to inspect and choose again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep decision'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reconsider'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      reconsiderReviewDecision(kitApi: widget.kitApi, reviewFrameId: frame.id);
      setState(() => _reviewError = null);
    }
  }

  Widget _decisionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required Key key,
  }) => Expanded(
    child: Material(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: key,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.65)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _patchPreview(SceneObject frame) {
    final body = patchProposalBody(widget.store.document, frame.id);
    final path = body?.props['path']?.toString() ?? '';
    final diff = body?.props['diff']?.toString() ?? '';
    final counts = patchDiffCounts(diff);
    final tokens = PaintScope.of(context);
    return _section('Patch proposal', [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path.isEmpty ? 'Waiting for a proposal' : path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              path.isEmpty
                  ? 'Connect Propose Patch and ask for one file change.'
                  : '${counts.added} added  ·  ${counts.removed} removed  ·  1 file',
              style: TextStyle(color: tokens.muted, fontSize: 12),
            ),
            if (path.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                validPatchProposal(body)
                    ? 'Ready for your review'
                    : 'Proposal changed; request a fresh proposal',
                style: TextStyle(
                  color: validPatchProposal(body)
                      ? tokens.accent
                      : tokens.danger,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (diff.isNotEmpty)
        PaintButton(
          key: const Key('preview-patch-diff'),
          label: 'Inspect colored diff',
          onPressed: () => showPatchDiffViewer(
            context: context,
            path: path,
            diff: diff,
            proposalId: body?.props[proposalIdProp]?.toString() ?? '',
          ),
        ),
      if (body != null && path.isNotEmpty) ...[
        const SizedBox(height: 8),
        PaintButton(
          key: const Key('export-patch-proposal'),
          label: 'Export proposal…',
          onPressed: () => _exportProposal(body),
        ),
      ],
    ]);
  }

  Widget _patchReview(SceneObject frame) {
    final proposal = connectedProposalFrame(widget.store.document, frame.id);
    final body = proposal == null
        ? null
        : patchProposalBody(widget.store.document, proposal.id);
    final valid = validPatchProposal(body);
    final decision = reviewDecisionOf(widget.store.document, frame.id);
    final tokens = PaintScope.of(context);
    final matches =
        valid &&
        reviewDecisionBody(
              widget.store.document,
              frame.id,
            )?.props[proposalIdProp] ==
            body?.props[proposalIdProp] &&
        reviewDecisionBody(
              widget.store.document,
              frame.id,
            )?.props[proposalFingerprintProp] ==
            body?.props[proposalFingerprintProp];
    final settled = matches && decision.isNotEmpty;
    final applied =
        settled &&
        _effects.records.any(
          (record) =>
              record['kind'] == 'apply' &&
              record['state'] == 'applied' &&
              record['proposalId'] == body?.props[proposalIdProp] &&
              record['proposalFingerprint'] ==
                  body?.props[proposalFingerprintProp],
        );
    final statusColor = decision == 'accept' ? tokens.success : tokens.danger;
    return _section('Review', [
      _readOnly(
        'File',
        body?.props['path']?.toString() ?? 'Connect a proposal',
      ),
      const SizedBox(height: 8),
      if (settled)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
            border: Border.all(color: statusColor.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                decision == 'accept'
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  decision == 'accept'
                      ? 'Accepted · ready for separate Apply'
                      : 'Rejected · file remains unchanged',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        )
      else
        _readOnly('Decision', 'Awaiting your choice'),
      const SizedBox(height: 10),
      if (valid) ...[
        PaintButton(
          key: const Key('review-open-diff'),
          label: 'Inspect colored diff',
          onPressed: () => showPatchDiffViewer(
            context: context,
            path: body!.props['path']?.toString() ?? '',
            diff: body.props['diff']?.toString() ?? '',
            proposalId: body.props[proposalIdProp]?.toString() ?? '',
          ),
        ),
        const SizedBox(height: 12),
        if (!settled)
          Row(
            children: [
              _decisionButton(
                key: const Key('review-reject'),
                label: 'Reject',
                icon: Icons.close,
                color: tokens.danger,
                onPressed: () => _review('reject', frame),
              ),
              const SizedBox(width: 10),
              _decisionButton(
                key: const Key('review-accept'),
                label: 'Accept',
                icon: Icons.check,
                color: tokens.success,
                onPressed: () => _review('accept', frame),
              ),
            ],
          )
        else if (!applied)
          TextButton(
            key: const Key('review-reconsider'),
            onPressed: () => _reconsider(frame),
            child: const Text('Reconsider decision…'),
          )
        else
          Text(
            'Applied decisions stay recorded. Use Revert on Apply Patch.',
            style: TextStyle(color: tokens.muted, fontSize: 11),
          ),
      ],
      if (_reviewError != null) Text(_reviewError!),
      const SizedBox(height: 8),
      Text(
        'Your choice is recorded. Only a separate Apply can write the file.',
        style: TextStyle(color: tokens.muted, fontSize: 11),
      ),
    ]);
  }

  Widget _writeScopePanel(SceneObject frame) {
    final tokens = PaintScope.of(context);
    final path = frame.props[writeScopePathProp]?.toString() ?? '';
    return _section('Write grant', [
      _readOnly('Folder', path.isEmpty ? 'No folder selected' : path),
      const SizedBox(height: 8),
      Text(
        'This is a separate permission. The Repository read grant cannot write.',
        style: TextStyle(color: tokens.muted, fontSize: 11),
      ),
      const SizedBox(height: 10),
      PaintButton(
        key: const Key('choose-write-scope'),
        label: path.isEmpty ? 'Choose write folder…' : 'Choose another folder…',
        onPressed: () => _chooseWriteScope(frame),
      ),
      if (path.isNotEmpty) ...[
        const SizedBox(height: 8),
        TextButton(
          key: const Key('remove-write-scope'),
          onPressed: () =>
              widget.kitApi.updateProps(frame.id, {writeScopePathProp: ''}),
          child: const Text('Remove folder from this board'),
        ),
      ],
    ]);
  }

  Widget _applyEffectPanel(SceneObject frame) {
    final tokens = PaintScope.of(context);
    final gate = applyPatchGate(widget.store.document, frame.id);
    final scope = connectedWriteScopeFrame(widget.store.document, frame.id);
    final scopePath = scope?.props[writeScopePathProp]?.toString() ?? '';
    final ready = !gate.inert && scopePath.isNotEmpty;
    final last = _effects.latestApplyFor(frame.id);
    final reverted = last == null
        ? false
        : _effects.wasReverted(last['id']?.toString() ?? '');
    return _section('Repository effect', [
      _readOnly(
        'Review',
        gate.inert ? gate.reason : 'Accepted proposal connected',
      ),
      _readOnly(
        'Write Scope',
        scopePath.isEmpty ? 'Connect a Write Scope' : scopePath,
      ),
      const SizedBox(height: 10),
      PaintButton(
        key: const Key('apply-patch-action'),
        label: _effectBusy ? 'Working…' : 'Verify and apply patch…',
        filled: true,
        onPressed: ready && !_effectBusy ? () => _applyPatch(frame) : null,
      ),
      if (last != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (reverted ? tokens.accent : tokens.success).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            reverted
                ? 'Reverted · original file restored'
                : 'Applied · preimage and observed diff recorded',
            style: TextStyle(
              color: reverted ? tokens.accent : tokens.success,
              fontSize: 12,
            ),
          ),
        ),
        if ((last['observedDiff']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          PaintButton(
            key: const Key('open-observed-diff'),
            label: 'Open observed diff',
            onPressed: () => showPatchDiffViewer(
              context: context,
              path: last['path']?.toString() ?? '',
              diff: last['observedDiff']?.toString() ?? '',
              proposalId: last['proposalId']?.toString() ?? '',
              observed: true,
            ),
          ),
        ],
        if (!reverted) ...[
          const SizedBox(height: 8),
          PaintButton(
            key: const Key('revert-patch-action'),
            label: 'Revert this file…',
            onPressed: scopePath.isNotEmpty && !_effectBusy
                ? () => _revertPatch(last['id']!.toString(), scopePath)
                : null,
          ),
        ],
      ],
      if (_effectMessage != null) ...[
        const SizedBox(height: 9),
        Text(
          _effectMessage!,
          style: TextStyle(color: tokens.ink, fontSize: 11),
        ),
      ],
      const SizedBox(height: 9),
      Text(
        'Board Undo does not undo file writes.',
        style: TextStyle(color: tokens.muted, fontSize: 11),
      ),
    ]);
  }

  Widget _checkSpecPanel(SceneObject frame) {
    final chosen = frame.props[checkPresetProp] == gitDiffCheckPreset;
    final tokens = PaintScope.of(context);
    return _section('Check specification', [
      _readOnly('Executable', 'Installed Git, resolved by Skapie'),
      _readOnly('Arguments', 'diff --check'),
      const SizedBox(height: 8),
      Text(
        'A trusted preset. There is no shell field and no model-supplied command.',
        style: TextStyle(color: tokens.muted, fontSize: 11),
      ),
      const SizedBox(height: 9),
      PaintButton(
        key: const Key('choose-git-diff-check'),
        label: chosen ? 'Git diff check chosen' : 'Choose Git diff check',
        onPressed: chosen
            ? null
            : () => widget.kitApi.updateProps(frame.id, {
                checkPresetProp: gitDiffCheckPreset,
              }),
      ),
    ]);
  }

  Future<void> _startCheck(
    SceneObject frame, {
    bool repeat = false,
    String? expectedResultId,
  }) async {
    if (_checkBusy) return;
    final scope = connectedCheckWriteScope(widget.store.document, frame.id);
    final root = scope?.props[writeScopePathProp]?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(repeat ? 'Repeat Git diff check?' : 'Run Git diff check?'),
        content: Text(
          'Skapie will run installed Git with exactly: diff --check\n\n'
          'Working folder: $root\n\n'
          'This process has repository write scope. Network access is allowed by the app sandbox, though this check does not request network access.'
          '${repeat ? '\n\nSkapie will check the live Write Scope again and create a new run record. Earlier evidence stays saved.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(repeat ? 'Run again' : 'Run check'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final current = widget.store.document;
    final currentScope = connectedCheckWriteScope(current, frame.id);
    final currentRoot =
        currentScope?.props[writeScopePathProp]?.toString() ?? '';
    if (!checkGate(current, frame.id).ready ||
        currentRoot != root ||
        (expectedResultId != null &&
            connectedCheckResult(current, frame.id)?.id != expectedResultId)) {
      setState(
        () => _checkMessage = 'Check setup changed. Review the cables and folder, then confirm again.',
      );
      return;
    }
    setState(() {
      _checkBusy = true;
      _checkMessage = 'Running bounded check…';
    });
    try {
      final attempt = await invokeRunCheck(
        kitApi: widget.kitApi,
        runFrameId: frame.id,
        permission: widget.writePermission,
        runner: widget.checkRunner,
        directoryExists: widget.checkDirectoryExists,
        beginEvidence: widget.controller == null
            ? null
            : (bodyId, details) =>
                  widget.controller!.beginCheckRun(bodyId, details),
        appendEvidence: widget.controller?.appendCheckEvent,
      );
      if (mounted) {
        setState(() => _checkMessage = attempt.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _checkMessage = 'Check could not finish: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _checkBusy = false);
      }
    }
  }

  Future<void> _repeatCheck(SceneObject resultFrame) async {
    final run = connectedRunCheckForResult(
      widget.store.document,
      resultFrame.id,
    );
    if (run == null) return;
    await _startCheck(run, repeat: true, expectedResultId: resultFrame.id);
  }

  Future<void> _cancelCheck() async {
    try {
      final signalled = await widget.checkRunner.cancel();
      if (mounted) {
        setState(
          () => _checkMessage = signalled
              ? 'Stop requested; waiting for the process group to settle…'
              : 'No running check was found.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _checkMessage = 'Stop uncertain: $error');
    }
  }

  Future<void> _stopCheckOnDispose() async {
    try {
      await widget.checkRunner.cancel();
    } catch (_) {
      // The widget is gone; the native timeout still bounds the process.
    }
  }

  Widget _runCheckPanel(SceneObject frame) {
    final gate = checkGate(widget.store.document, frame.id);
    final scope = connectedCheckWriteScope(widget.store.document, frame.id);
    final root = scope?.props[writeScopePathProp]?.toString() ?? '';
    final tokens = PaintScope.of(context);
    return _section('Execution grant', [
      _readOnly('Check', 'Installed Git · diff --check'),
      _readOnly('Working folder', root.isEmpty ? 'Connect Write Scope' : root),
      _readOnly('Network', 'Allowed by app sandbox'),
      _readOnly('Time limit', '30 seconds'),
      const SizedBox(height: 7),
      Text(
        'This check can have file effects. A working folder is not process isolation.',
        style: TextStyle(color: tokens.muted, fontSize: 11),
      ),
      if (!gate.ready) ...[
        const SizedBox(height: 7),
        Text(gate.reason, style: TextStyle(color: tokens.danger, fontSize: 11)),
      ],
      const SizedBox(height: 10),
      PaintButton(
        key: const Key('run-check-action'),
        label: _checkBusy ? 'Running…' : 'Run Git diff check…',
        filled: true,
        onPressed: gate.ready && !_checkBusy ? () => _startCheck(frame) : null,
      ),
      if (_checkBusy) ...[
        const SizedBox(height: 8),
        PaintButton(
          key: const Key('cancel-check-action'),
          label: 'Stop check',
          onPressed: _cancelCheck,
        ),
      ],
      if (_checkMessage != null) ...[
        const SizedBox(height: 8),
        Text(_checkMessage!, style: TextStyle(color: tokens.ink, fontSize: 11)),
      ],
    ]);
  }

  Widget _checkResultPanel(SceneObject frame) {
    final body = checkResultBody(widget.store.document, frame.id);
    final props = body?.props ?? const <String, Object?>{};
    final outcome = props['checkOutcome']?.toString() ?? '';
    final tokens = PaintScope.of(context);
    final error = props['checkError']?.toString() ?? '';
    final runs = body == null
        ? const <RunRecord>[]
        : widget.controller?.ledger
                  .runsFor(body.id)
                  .where((run) => run.kind == 'check')
                  .toList() ??
              const <RunRecord>[];
    final latestRun = runs.lastOrNull;
    final outputEvents = latestRun?.events
        .where((event) => event.kind == RunEventKind.checkOutput)
        .toList();
    final latestOutput = outputEvents?.lastOrNull;
    final latestOutputText = latestRun == null || latestOutput == null
        ? ''
        : widget.controller?.ledger.inspectText(latestRun, latestOutput) ?? '';
    const finishedOutcomes = {
      'exit_0',
      'nonzero_exit',
      'timeout',
      'cancelled',
      'infrastructure_error',
    };
    final hasPastResult =
        finishedOutcomes.contains(outcome) ||
        runs.any(
          (run) => run.events.any(
            (event) => event.kind == RunEventKind.checkFinished,
          ),
        );
    final repeatGate = repeatCheckGate(widget.store.document, frame.id);
    return _section('Check result', [
      _readOnly(
        'Outcome',
        outcome.isEmpty ? 'No check run yet' : outcome.replaceAll('_', ' '),
      ),
      if (outcome.isNotEmpty) ...[
        _readOnly('Command', 'git diff --check'),
        _readOnly(
          'Git status',
          props['checkGitStateKnown'] == true
              ? props['checkGitChanged'] == true
                    ? 'Changed during check'
                    : 'Unchanged'
              : 'Final state unavailable',
        ),
        _readOnly('Network', 'Allowed by app sandbox'),
        if (latestOutputText.isNotEmpty)
          _readOnly(
            'Latest redacted output',
            latestOutputText.trim().length > 160
                ? '${latestOutputText.trim().substring(0, 160)}…'
                : latestOutputText.trim(),
          ),
        if (props['checkTruncated'] == true)
          _readOnly('Output', 'Truncated at the safety limit'),
        if (error.isNotEmpty) _readOnly('Issue', error),
        if (props['checkStopUncertain'] == true)
          Text(
            'Stop is uncertain; inspect running processes.',
            style: TextStyle(color: tokens.danger, fontSize: 11),
          ),
        const SizedBox(height: 8),
        if (runs.isNotEmpty)
          PaintButton(
            key: const Key('open-check-ledger'),
            label: 'Open check run ledger (${runs.length})',
            onPressed: () => _openCheckLedger(runs),
          ),
        if (hasPastResult) ...[
          const SizedBox(height: 8),
          PaintButton(
            key: const Key('repeat-check-action'),
            label: _checkBusy ? 'Running…' : 'Repeat Check…',
            filled: true,
            onPressed: repeatGate.ready && !_checkBusy
                ? () => _repeatCheck(frame)
                : null,
          ),
          if (!repeatGate.ready) ...[
            const SizedBox(height: 6),
            Text(
              repeatGate.reason,
              style: TextStyle(color: tokens.danger, fontSize: 11),
            ),
          ],
          if (_checkBusy) ...[
            const SizedBox(height: 8),
            PaintButton(
              key: const Key('cancel-repeat-check-action'),
              label: 'Stop check',
              onPressed: _cancelCheck,
            ),
          ],
          if (_checkMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _checkMessage!,
              style: TextStyle(color: tokens.ink, fontSize: 11),
            ),
          ],
        ],
        const SizedBox(height: 6),
        Text(
          'Exit 0 means only that this command exited 0. The LLM Context cable carries this short result, not the transcript.',
          style: TextStyle(color: tokens.muted, fontSize: 11),
        ),
      ],
    ]);
  }

  void _openCheckLedger(List<RunRecord> runs) {
    final ledger = widget.controller?.ledger;
    if (ledger == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check run ledger'),
        content: SizedBox(
          width: 720,
          height: 540,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Viewing a saved run never starts a check.'),
              ),
              for (final run in runs.reversed)
                ExpansionTile(
                  key: Key('check-ledger-${run.id}'),
                  title: Text(
                    '${run.id} · ${run.events.lastOrNull?.payload['outcome']?.toString().replaceAll('_', ' ') ?? 'Running'}',
                  ),
                  subtitle: Text(
                    run.events.firstOrNull?.at.toLocal().toString() ?? '',
                  ),
                  children: [
                    for (final event in run.events)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(runEventEvidenceLine(event)),
                            SelectableText(
                              event.kind == RunEventKind.checkOutput
                                  ? '${event.payload['phase']} ${event.payload['stream']} · ${event.payload['at'] ?? event.at.toIso8601String()}\n${ledger.inspectText(run, event) ?? ''}'
                                  : [
                                      'at: ${event.at.toIso8601String()}',
                                      for (final entry in event.payload.entries)
                                        '${entry.key}: ${ledger.inspectValue(run, event, entry.key) ?? ''}',
                                    ].join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _effects =
        widget.effectLog ??
        PatchEffectLog.besideScene(widget.store.sceneFilePath);
    _loadEffects();
    widget.store.addListener(_onStore);
    widget.selection.addListener(_onSelection);
    widget.controller?.addListener(_onAgent);
    _contentFocus.addListener(_onContentFocus);
    _bindObject(force: true);
  }

  @override
  void didUpdateWidget(InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
      _effects =
          widget.effectLog ??
          PatchEffectLog.besideScene(widget.store.sceneFilePath);
      _loadEffects();
    }
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelection);
      widget.selection.addListener(_onSelection);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onAgent);
      widget.controller?.addListener(_onAgent);
    }
    _bindObject(force: true);
  }

  @override
  void dispose() {
    if (_checkBusy) {
      unawaited(_stopCheckOnDispose());
    }
    _debounce?.cancel();
    widget.store.removeListener(_onStore);
    widget.selection.removeListener(_onSelection);
    widget.controller?.removeListener(_onAgent);
    _contentFocus.removeListener(_onContentFocus);
    _x.dispose();
    _y.dispose();
    _content.dispose();
    _contentFocus.dispose();
    _fontSize.dispose();
    _color.dispose();
    _fill.dispose();
    _label.dispose();
    _name.dispose();
    _nameFocus.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _onStore() {
    widget.selection.syncToDocument(widget.store.document);
    if (_debounce?.isActive ?? false) {
      setState(() {});
      return;
    }
    _bindObject(force: false);
    setState(() {});
  }

  void _onSelection() {
    _bindObject(force: true);
    setState(() {});
  }

  void _onAgent() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onContentFocus() {
    if (_contentFocus.hasFocus) {
      return;
    }
    _bindObject(force: true);
    setState(() {});
  }

  SceneObject? get _object {
    final id = widget.selection.selectedId;
    if (id == null) {
      return null;
    }
    return widget.store.document.objectById(id);
  }

  SceneObject? get _frame {
    final object = _object;
    if (object == null) {
      return null;
    }
    return kitFrameForSelection(
          document: widget.store.document,
          selectedId: object.id,
        ) ??
        object;
  }

  void _bindObject({required bool force}) {
    final object = _object;
    final frame = _frame;
    if (object == null || frame == null) {
      _boundId = null;
      return;
    }
    final idChanged = _boundId != object.id;
    final fill = kitHasCustomFill(frame)
        ? _string(frame.props, 'fill')
        : colorToHex(PaintTokens.dark().panel);
    if (!force && !idChanged) {
      _syncField(
        _content,
        _string(object.props, 'content'),
        skip: _contentFocus.hasFocus,
      );
      _syncField(_x, _fmt(frame.x));
      _syncField(_y, _fmt(frame.y));
      _syncField(_fontSize, _string(object.props, 'fontSize'));
      _syncField(_color, _string(object.props, 'color'));
      _syncField(_fill, fill);
      _syncField(_label, _string(object.props, 'label'));
      _syncField(
        _name,
        kitDisplayName(widget.store.document, frame),
        skip: _nameFocus.hasFocus,
      );
      _syncField(
        _description,
        _string(frame.props, 'description'),
        skip: _descriptionFocus.hasFocus,
      );
      return;
    }
    _boundId = object.id;
    _syncField(_x, _fmt(frame.x));
    _syncField(_y, _fmt(frame.y));
    _syncField(
      _content,
      _string(object.props, 'content'),
      skip: !idChanged && _contentFocus.hasFocus,
    );
    _syncField(_fontSize, _string(object.props, 'fontSize'));
    _syncField(_color, _string(object.props, 'color'));
    _syncField(_fill, fill);
    _syncField(_label, _string(object.props, 'label'));
    _syncField(
      _name,
      kitDisplayName(widget.store.document, frame),
      skip: !idChanged && _nameFocus.hasFocus,
    );
    _syncField(
      _description,
      _string(frame.props, 'description'),
      skip: !idChanged && _descriptionFocus.hasFocus,
    );
  }

  void _syncField(
    TextEditingController controller,
    String value, {
    bool skip = false,
  }) {
    if (skip) {
      return;
    }
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String _fmt(double value) {
    final rounded = (value * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toString();
  }

  String _string(Map<String, Object?> props, String key) {
    final value = props[key];
    return value == null ? '' : '$value';
  }

  void _applyProps(
    Map<String, Object?> patch, {
    bool immediate = false,
    String? id,
  }) {
    final target = id ?? widget.selection.selectedId;
    if (target == null) {
      return;
    }
    void commit() {
      widget.kitApi.updateProps(target, patch);
    }

    _debounce?.cancel();
    if (immediate) {
      commit();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), commit);
  }

  void _applyAppearance(Map<String, Object?> patch, {bool immediate = false}) {
    final frame = _frame;
    if (frame == null) {
      return;
    }
    _applyProps(patch, immediate: immediate, id: frame.id);
  }

  void _rename(String value, {bool immediate = false}) {
    final frame = _frame;
    final name = value.trim();
    if (frame == null || name.isEmpty || !isKitObject(frame)) {
      return;
    }
    final members =
        kitMembers(document: widget.store.document, selectedId: frame.id) ??
        [frame];
    void commit() {
      for (final member in members) {
        widget.kitApi.updateProps(member.id, {kitNameProp: name});
      }
    }

    _debounce?.cancel();
    if (immediate) {
      commit();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), commit);
  }

  void _applyFrame({double? x, double? y}) {
    final frame = _frame;
    if (frame == null) {
      return;
    }
    final members =
        kitMembers(document: widget.store.document, selectedId: frame.id) ??
        [frame];
    final dx = x == null ? 0.0 : x - frame.x;
    final dy = y == null ? 0.0 : y - frame.y;
    if (dx == 0 && dy == 0) {
      return;
    }
    for (final member in members) {
      widget.kitApi.updateFrame(
        id: member.id,
        x: x == null ? null : member.x + dx,
        y: y == null ? null : member.y + dy,
      );
    }
  }

  void _delete() {
    final id = widget.selection.selectedId;
    if (id == null) {
      return;
    }
    removeKitSelection(kitApi: widget.kitApi, selectedId: id);
    widget.selection.syncToDocument(widget.store.document);
  }

  Future<void> _chooseRepository(SceneObject frame) async {
    try {
      final path = await _repositoryPermission.chooseDirectory();
      if (!mounted || path == null || path.isEmpty) {
        return;
      }
      if (widget.store.document.objectById(frame.id) == null) {
        return;
      }
      widget.kitApi.updateProps(frame.id, {repositoryPathProp: path});
      final name = path.split('/').where((part) => part.isNotEmpty).last;
      for (final member
          in kitMembers(
                document: widget.store.document,
                selectedId: frame.id,
              ) ??
              const <SceneObject>[]) {
        if (member.props[skapieRoleProp] == 'body') {
          widget.kitApi.updateProps(member.id, {
            'content': '$name\nRead-only repository',
          });
        }
      }
      setState(() => _repositoryError = null);
    } catch (error) {
      if (mounted) {
        setState(() => _repositoryError = '$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cableId = widget.selection.selectedCableId;
    if (cableId != null) {
      return ConnectionInspector(
        kitApi: widget.kitApi,
        selection: widget.selection,
        cableId: cableId,
        controller: widget.controller,
        onCut: widget.onCutCable,
      );
    }
    final object = _object;
    final frame = _frame;
    if (object == null || frame == null) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    final llmBody = llmKitBodyForSelection(
      document: widget.store.document,
      selectedId: object.id,
    );
    final controller = widget.controller;
    final typeLabel = llmBody != null
        ? 'LLM'
        : kitIdOf(object) == codingRepositoryKitId
        ? 'Repository'
        : isWorldToolKit(object)
        ? kitNameStem(kitIdOf(object)!)
        : object.type;

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Inspector', style: textTheme.labelLarge),
                    _section('Type', [
                      _readOnly('', typeLabel, hideLabel: true),
                    ]),
                    _section('Identity', [
                      if (isKitObject(object))
                        _field(
                          key: const Key('inspector-id'),
                          label: 'Id',
                          controller: _name,
                          focusNode: _nameFocus,
                          onChanged: _rename,
                          onSubmitted: (value) =>
                              _rename(value, immediate: true),
                        )
                      else
                        _readOnly('Id', object.id),
                    ]),
                    if (llmBody == null)
                      _section('Transform', [
                        PaintHover(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Locked'),
                            subtitle: const Text(
                              'Select and delete ok, no move',
                            ),
                            value: object.locked,
                            onChanged: (value) {
                              widget.kitApi.setLocked(object.id, value);
                            },
                          ),
                        ),
                        _field(
                          label: 'X',
                          controller: _x,
                          onSubmitted: (value) {
                            final parsed = double.tryParse(value);
                            if (parsed != null) {
                              _applyFrame(x: parsed);
                            }
                          },
                        ),
                        _field(
                          label: 'Y',
                          controller: _y,
                          onSubmitted: (value) {
                            final parsed = double.tryParse(value);
                            if (parsed != null) {
                              _applyFrame(y: parsed);
                            }
                          },
                        ),
                      ]),
                    if (frame.type == boxTypeId || isKitObject(object))
                      _section('Appearance', [
                        if (isKitObject(object))
                          _swatches(frame)
                        else
                          _field(
                            key: const Key('inspector-fill'),
                            label: 'Fill',
                            controller: _fill,
                            onChanged: (value) =>
                                _applyAppearance({'fill': value}),
                            onSubmitted: (value) => _applyAppearance({
                              'fill': value,
                            }, immediate: true),
                          ),
                      ]),
                    if (llmBody != null && controller != null)
                      _section('Model / IO', [
                        LlmKitInput(
                          body: llmBody,
                          kitApi: widget.kitApi,
                          controller: controller,
                        ),
                      ]),
                    if (llmBody != null && controller != null)
                      LlmRequestInformation(
                        body: llmBody,
                        kitApi: widget.kitApi,
                        controller: controller,
                      ),
                    if (llmBody != null && controller != null)
                      _toolActivity(llmBody.id, controller),
                    if (llmBody != null && controller != null)
                      _runEvidence(llmBody.id, controller),
                    if (kitIdOf(object) == codingRepositoryKitId)
                      _section('Repository', [
                        Tooltip(
                          message:
                              frame.props[repositoryPathProp]?.toString() ??
                              'No folder selected',
                          child: _readOnly(
                            'Folder',
                            frame.props[repositoryPathProp]
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ==
                                    true
                                ? frame.props[repositoryPathProp].toString()
                                : 'Choose a folder',
                          ),
                        ),
                        _readOnly('Permission', 'Read-only'),
                        _readOnly(
                          'Availability',
                          (frame.props[repositoryPathProp]?.toString().trim() ??
                                      '')
                                  .isEmpty
                              ? 'Folder not chosen'
                              : 'Available',
                        ),
                        PaintButton(
                          key: const Key('choose-repository'),
                          label: 'Choose folder',
                          onPressed: () => _chooseRepository(frame),
                        ),
                        if (_repositoryError != null)
                          Text(
                            _repositoryError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ]),
                    if (kitIdOf(frame) == codingPatchProposalKitId)
                      _patchPreview(frame),
                    if (kitIdOf(frame) == codingReviewDecisionKitId)
                      _patchReview(frame),
                    if (kitIdOf(frame) == codingWriteScopeKitId)
                      _writeScopePanel(frame),
                    if (kitIdOf(frame) == codingApplyPatchKitId)
                      _applyEffectPanel(frame),
                    if (kitIdOf(frame) == codingCheckSpecKitId)
                      _checkSpecPanel(frame),
                    if (kitIdOf(frame) == codingRunCheckKitId)
                      _runCheckPanel(frame),
                    if (kitIdOf(frame) == codingCheckResultKitId)
                      _checkResultPanel(frame),
                    if (llmBody == null &&
                        object.type != boxTypeId &&
                        !isWorldToolKit(object) &&
                        kitIdOf(object) != codingRepositoryKitId &&
                        kitIdOf(object) != codingPatchProposalKitId &&
                        kitIdOf(object) != codingReviewDecisionKitId &&
                        kitIdOf(object) != codingApplyPatchKitId &&
                        kitIdOf(object) != codingWriteScopeKitId &&
                        kitIdOf(object) != codingCheckSpecKitId &&
                        kitIdOf(object) != codingRunCheckKitId &&
                        kitIdOf(object) != codingCheckResultKitId)
                      _section('Content', _typeFields(object)),
                    if (llmBody != null)
                      _section('Tools', [
                        _readOnly('Attached', () {
                          final names = attachedToolNames(
                            kitApi: widget.kitApi,
                            llmBodyId: llmBody.id,
                          );
                          return names.isEmpty ? 'none' : names.join(', ');
                        }()),
                      ]),
                    if (isWorldToolKit(object) || isWorldToolKit(frame))
                      _section('Description', [
                        _field(
                          key: const Key('tool-description'),
                          label: 'Description',
                          controller: _description,
                          focusNode: _descriptionFocus,
                          onChanged: (value) =>
                              _applyProps({'description': value}, id: frame.id),
                          onSubmitted: (value) => _applyProps(
                            {'description': value},
                            immediate: true,
                            id: frame.id,
                          ),
                        ),
                      ]),
                    if (isWorldToolKit(object) ||
                        kitIdOf(object) == boardTextKitId)
                      _section(
                        'Allowed connections',
                        _allowedConnections(object),
                      ),
                    if (frame.props['requiresRepository'] == true)
                      _section('Repository input', _repositoryInputs(frame)),
                    if (kitIdOf(object) == codingRepositoryKitId)
                      _section('In / Out', _repositoryOutputs(frame)),
                    if (kitIdOf(object) == harnessConversationKitId)
                      _section(
                        'Allowed connections',
                        _conversationConnections(object),
                      ),
                    if (llmBody != null)
                      _section(
                        'Allowed connections',
                        _llmAllowedConnections(llmBody),
                      ),
                    const SizedBox(height: PaintTokens.space),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: _section('Actions', [
                PaintButton(label: 'Delete', onPressed: _delete),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatches(SceneObject frame) {
    final tokens = PaintScope.of(context);
    final selected = colorToHex(kitAccentColor(frame));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        key: const Key('kit-swatches'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final swatch in kitSwatches)
            GestureDetector(
              key: ValueKey('kit-swatch-${colorToHex(swatch)}'),
              onTap: () {
                _applyAppearance({
                  kitAccentProp: colorToHex(swatch),
                }, immediate: true);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorToHex(swatch) == selected
                        ? tokens.ink
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 18, height: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int? _evidencePage;
  String? _evidenceRunId;
  String? _hoverEvent;

  void _openRunEvent(
    RunRecord run,
    RunEvent event,
    AgentController controller,
  ) {
    final stored = controller.ledger.inspectText(run, event);
    final body = (stored == null || stored.isEmpty)
        ? runEventInspectBody(event)
        : stored;
    showFullScreenTextEditor(
      context: context,
      title: runEventLabel(event.kind),
      text: body,
      details: runEventInspectAside(event),
      readOnly: true,
      surfaceKey: const Key('run-event-fullscreen'),
      fieldKey: const Key('run-event-field'),
      closeKey: const Key('run-event-close'),
    );
  }

  Widget _timelineEvent(
    RunRecord run,
    RunEvent event,
    AgentController controller,
    PaintTokens tokens,
  ) {
    final key = '${run.id}:${event.sequence}';
    final hover = _hoverEvent == key;
    final failed =
        event.kind == RunEventKind.runFailed || event.payload['ok'] == false;
    final succeeded =
        event.kind == RunEventKind.toolCallFinished &&
        event.payload['ok'] != false;
    final color = failed
        ? tokens.danger
        : succeeded
        ? tokens.success
        : tokens.ink;
    return Padding(
      key: ValueKey('run-event-${run.id}-${event.sequence}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoverEvent = key),
        onExit: (_) {
          if (_hoverEvent == key) {
            setState(() => _hoverEvent = null);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: hover
                ? tokens.ink.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                  child: Text(
                    runEventSummary(event),
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('run-event-inspect-${run.id}-${event.sequence}'),
                tooltip: 'Inspect',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () => _openRunEvent(run, event, controller),
                icon: Icon(Icons.search, size: 16, color: tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _runEvidence(String bodyId, AgentController controller) {
    final runs = controller.ledger.runsFor(bodyId);
    RunRecord? run;
    var runIndex = -1;
    if (runs.isNotEmpty) {
      final selected = _evidenceRunId;
      runIndex = selected == null
          ? runs.length - 1
          : runs.indexWhere((item) => item.id == selected);
      if (runIndex < 0) {
        runIndex = runs.length - 1;
      }
      run = runs[runIndex];
    }
    final page = runEvidencePage(run, _evidencePage ?? 1 << 20);
    final tokens = PaintScope.of(context);
    return _section('Run evidence', [
      ExpansionTile(
        key: ValueKey('run-evidence-$bodyId'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: run == null
            ? Text(
                'No saved run',
                style: TextStyle(color: tokens.ink, fontSize: 12),
              )
            : Row(
                children: [
                  IconButton(
                    key: const Key('run-evidence-previous-run'),
                    tooltip: 'Previous run',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    onPressed: runIndex > 0
                        ? () {
                            controller.clearTrace();
                            setState(() {
                              _evidenceRunId = runs[runIndex - 1].id;
                              _evidencePage = null;
                            });
                          }
                        : null,
                    icon: Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: runIndex > 0 ? tokens.ink : tokens.muted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      run.id,
                      key: const Key('run-evidence-name'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tokens.ink, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    key: const Key('run-evidence-identify'),
                    tooltip: 'Identify',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    onPressed: () => controller.identifyRun(run!),
                    icon: Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: tokens.ink,
                    ),
                  ),
                  IconButton(
                    key: const Key('run-evidence-next-run'),
                    tooltip: 'Next run',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    onPressed: runIndex < runs.length - 1
                        ? () {
                            controller.clearTrace();
                            setState(() {
                              _evidenceRunId = runs[runIndex + 1].id;
                              _evidencePage = null;
                            });
                          }
                        : null,
                    icon: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: runIndex < runs.length - 1
                          ? tokens.ink
                          : tokens.muted,
                    ),
                  ),
                ],
              ),
        children: [
          if (controller.ledger.historyWarning)
            Text(
              'Run history is large. Older runs are kept.',
              key: const Key('run-history-warning'),
              style: TextStyle(color: tokens.danger, fontSize: 12),
            ),
          if (run == null)
            _readOnly('', 'Run a reader to record events', hideLabel: true),
          for (final event in page.events)
            _timelineEvent(run!, event, controller, tokens),
          if (page.pageCount > 1)
            Row(
              children: [
                TextButton(
                  key: const Key('run-evidence-previous'),
                  onPressed: page.page > 0
                      ? () => setState(() => _evidencePage = page.page - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                Text(
                  '${page.page + 1} / ${page.pageCount}',
                  style: TextStyle(color: tokens.muted, fontSize: 11),
                ),
                TextButton(
                  key: const Key('run-evidence-next'),
                  onPressed: page.page < page.pageCount - 1
                      ? () => setState(() => _evidencePage = page.page + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    ]);
  }

  Widget _toolActivity(String bodyId, AgentController controller) {
    final activities = controller.toolActivitiesFor(bodyId);
    final running = controller.runningBodyId == bodyId;
    final tokens = PaintScope.of(context);
    return _section('Run activity', [
      ExpansionTile(
        key: ValueKey('tool-activity-$bodyId'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          running && controller.activeToolFrameId != null
              ? 'Using a tool · ${activities.length} call(s)'
              : '${activities.length} tool call(s)',
          style: TextStyle(color: tokens.ink, fontSize: 12),
        ),
        children: [
          if (activities.isEmpty)
            _readOnly(
              '',
              running
                  ? 'Waiting for tool calls'
                  : 'No tool calls in the last run',
              hideLabel: true,
            ),
          for (final activity in activities)
            ExpansionTile(
              key: ValueKey('tool-call-${activity.callId}'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                activity.name,
                style: TextStyle(color: tokens.ink, fontSize: 12),
              ),
              subtitle: Text(switch (activity.state) {
                AgentToolActivityState.running => 'Running',
                AgentToolActivityState.completed => 'Completed',
                AgentToolActivityState.failed => 'Failed',
              }, style: TextStyle(color: tokens.muted, fontSize: 11)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    'Arguments\n${activity.argumentsJson}\n\nResult\n${activity.result ?? 'Waiting'}',
                    style: TextStyle(
                      color: tokens.ink,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ]);
  }

  List<Widget> _allowedConnections(SceneObject object) {
    final bodies = llmBodies(widget.store.document);
    if (bodies.isEmpty) {
      return [_readOnly('', 'None on the board', hideLabel: true)];
    }
    if (isWorldToolKit(object)) {
      return [
        for (final body in bodies)
          _connectionRow(
            kit: body,
            connected: kitHasLink(object, to: body.id, port: llmToolsPort),
            onTap: () {
              if (kitHasLink(object, to: body.id, port: llmToolsPort)) {
                detachToolKit(
                  kitApi: widget.kitApi,
                  toolObjectId: object.id,
                  llmBodyId: body.id,
                );
              } else {
                attachToolKit(
                  kitApi: widget.kitApi,
                  toolObjectId: object.id,
                  llmBodyId: body.id,
                );
              }
            },
          ),
      ];
    }
    final frame = _frame ?? object;
    return [
      for (final body in bodies) ...[
        _connectionRow(
          kit: body,
          detail: 'Input',
          keyId: 'input-${body.id}',
          connected: kitHasLink(frame, to: body.id, port: llmInputPort),
          onTap: () => _toggleText(
            objectId: object.id,
            bodyId: body.id,
            port: llmInputPort,
            connected: kitHasLink(frame, to: body.id, port: llmInputPort),
          ),
        ),
        _connectionRow(
          kit: body,
          detail: 'Context',
          keyId: 'context-${body.id}',
          connected: kitHasLink(frame, to: body.id, port: llmContextPort),
          onTap: () => _toggleText(
            objectId: object.id,
            bodyId: body.id,
            port: llmContextPort,
            connected: kitHasLink(frame, to: body.id, port: llmContextPort),
          ),
        ),
      ],
    ];
  }

  List<Widget> _repositoryInputs(SceneObject toolFrame) {
    final repositories = repositoryFrames(widget.store.document);
    if (repositories.isEmpty) {
      return [_readOnly('', 'Add a Repository kit', hideLabel: true)];
    }
    return [
      for (final repository in repositories)
        _connectionRow(
          kit: repository,
          keyId: 'repository-${repository.id}',
          connected: kitHasLink(
            repository,
            to: toolFrame.id,
            port: repositoryPort,
          ),
          onTap: () => _toggleRepository(repository.id, toolFrame.id),
        ),
    ];
  }

  List<Widget> _repositoryOutputs(SceneObject repositoryFrame) {
    final tools = [
      for (final frame in toolFrames(widget.store.document))
        if (frame.props['requiresRepository'] == true) frame,
    ];
    if (tools.isEmpty) {
      return [_readOnly('', 'Add a repository tool kit', hideLabel: true)];
    }
    return [
      for (final tool in tools)
        _connectionRow(
          kit: tool,
          keyId: 'repository-tool-${tool.id}',
          connected: kitHasLink(
            repositoryFrame,
            to: tool.id,
            port: repositoryPort,
          ),
          onTap: () => _toggleRepository(repositoryFrame.id, tool.id),
        ),
    ];
  }

  void _toggleRepository(String repositoryId, String toolId) {
    final repository = widget.store.document.objectById(repositoryId);
    if (repository == null) {
      return;
    }
    if (kitHasLink(repository, to: toolId, port: repositoryPort)) {
      removeKitLink(
        kitApi: widget.kitApi,
        objectId: repositoryId,
        to: toolId,
        port: repositoryPort,
      );
    } else {
      connectRepositoryToTool(
        kitApi: widget.kitApi,
        repositoryFrameId: repositoryId,
        toolFrameId: toolId,
      );
    }
  }

  void _toggleText({
    required String objectId,
    required String bodyId,
    required String port,
    required bool connected,
  }) {
    if (connected) {
      disconnectText(
        kitApi: widget.kitApi,
        textObjectId: objectId,
        llmBodyId: bodyId,
        port: port,
      );
      return;
    }
    connectTextToLlm(
      kitApi: widget.kitApi,
      textObjectId: objectId,
      llmBodyId: bodyId,
      port: port,
    );
  }

  List<Widget> _llmAllowedConnections(SceneObject body) {
    final document = widget.store.document;
    final texts = textFrames(document);
    final tools = toolFrames(document);
    final others = [
      for (final other in llmBodies(document))
        if (other.id != body.id) other,
    ];
    return [
      _portHeading('Input'),
      ..._textPortRows(body, texts, llmInputPort),
      _portHeading('Context'),
      ..._textPortRows(body, texts, llmContextPort),
      _portHeading('Tools'),
      if (tools.isEmpty)
        _readOnly('', 'None on the board', hideLabel: true)
      else
        for (final tool in tools)
          _connectionRow(
            kit: tool,
            keyId: 'tools-${tool.id}',
            connected: kitHasLink(tool, to: body.id, port: llmToolsPort),
            onTap: () {
              if (kitHasLink(tool, to: body.id, port: llmToolsPort)) {
                detachToolKit(
                  kitApi: widget.kitApi,
                  toolObjectId: tool.id,
                  llmBodyId: body.id,
                );
              } else {
                attachToolKit(
                  kitApi: widget.kitApi,
                  toolObjectId: tool.id,
                  llmBodyId: body.id,
                );
              }
            },
          ),
      _portHeading('Conversation'),
      ..._conversationPortRows(body),
      _portHeading('Output'),
      if (texts.isEmpty && others.isEmpty)
        _readOnly('', 'None on the board', hideLabel: true)
      else ...[
        for (final text in texts)
          _connectionRow(
            kit: text,
            keyId: 'output-text-${text.id}',
            connected: kitHasLink(body, to: text.id, port: llmTextOutPort),
            onTap: () => _toggleOutput(
              sourceId: body.id,
              targetId: text.id,
              port: llmTextOutPort,
              connected: kitHasLink(body, to: text.id, port: llmTextOutPort),
            ),
          ),
        for (final other in others) ...[
          _connectionRow(
            kit: other,
            detail: 'Input',
            keyId: 'output-input-${other.id}',
            connected: kitHasLink(body, to: other.id, port: llmInputPort),
            onTap: () => _toggleOutput(
              sourceId: body.id,
              targetId: other.id,
              port: llmInputPort,
              connected: kitHasLink(body, to: other.id, port: llmInputPort),
            ),
          ),
          _connectionRow(
            kit: other,
            detail: 'Context',
            keyId: 'output-context-${other.id}',
            connected: kitHasLink(body, to: other.id, port: llmContextPort),
            onTap: () => _toggleOutput(
              sourceId: body.id,
              targetId: other.id,
              port: llmContextPort,
              connected: kitHasLink(body, to: other.id, port: llmContextPort),
            ),
          ),
        ],
      ],
    ];
  }

  List<Widget> _conversationConnections(SceneObject object) {
    final bodies = llmBodies(widget.store.document);
    if (bodies.isEmpty) {
      return [_readOnly('', 'None on the board', hideLabel: true)];
    }
    final frame = _frame ?? object;
    return [
      for (final body in bodies)
        _connectionRow(
          kit: body,
          detail: 'Conversation',
          keyId: 'conversation-${body.id}',
          connected: kitHasLink(frame, to: body.id, port: llmConversationPort),
          onTap: () => _toggleText(
            objectId: object.id,
            bodyId: body.id,
            port: llmConversationPort,
            connected: kitHasLink(
              frame,
              to: body.id,
              port: llmConversationPort,
            ),
          ),
        ),
    ];
  }

  List<Widget> _conversationPortRows(SceneObject body) {
    final conversations = conversationFrames(widget.store.document);
    if (conversations.isEmpty) {
      return [_readOnly('', 'None on the board', hideLabel: true)];
    }
    return [
      for (final frame in conversations)
        _connectionRow(
          kit: frame,
          keyId: 'conversation-${frame.id}',
          connected: kitHasLink(frame, to: body.id, port: llmConversationPort),
          onTap: () => _toggleText(
            objectId: frame.id,
            bodyId: body.id,
            port: llmConversationPort,
            connected: kitHasLink(
              frame,
              to: body.id,
              port: llmConversationPort,
            ),
          ),
        ),
    ];
  }

  List<Widget> _textPortRows(
    SceneObject body,
    List<SceneObject> texts,
    String port,
  ) {
    if (texts.isEmpty) {
      return [_readOnly('', 'None on the board', hideLabel: true)];
    }
    return [
      for (final text in texts)
        _connectionRow(
          kit: text,
          keyId: '$port-${text.id}',
          connected: kitHasLink(text, to: body.id, port: port),
          onTap: () => _toggleText(
            objectId: text.id,
            bodyId: body.id,
            port: port,
            connected: kitHasLink(text, to: body.id, port: port),
          ),
        ),
    ];
  }

  void _toggleOutput({
    required String sourceId,
    required String targetId,
    required String port,
    required bool connected,
  }) {
    if (connected) {
      disconnectLlmOutput(
        kitApi: widget.kitApi,
        sourceBodyId: sourceId,
        targetBodyId: targetId,
        port: port,
      );
      return;
    }
    connectLlmOutput(
      kitApi: widget.kitApi,
      sourceBodyId: sourceId,
      targetBodyId: targetId,
      port: port,
    );
  }

  List<String> _connectionFacts(SceneObject frame) {
    final document = widget.store.document;
    final facts = <String>[];
    final toolName = _memberText(frame, 'toolName');
    final display = kitDisplayName(document, frame);
    if (toolName.isNotEmpty && toolName != display) {
      facts.add(toolName);
    }
    if (frame.props['requiresRepository'] == true) {
      final repository = _linkedRepository(frame);
      facts.add(
        repository == null
            ? 'No repository'
            : kitDisplayName(document, repository),
      );
      facts.add('Read-only');
      facts.add(_repositoryAvailability(repository));
    } else if (isWorldToolKit(frame)) {
      facts.add('Available');
    }
    if (kitIdOf(frame) == codingRepositoryKitId) {
      facts.add('Read-only');
      facts.add(_repositoryAvailability(frame));
    }
    final last = frame.props[toolLastUsedProp]?.toString().trim() ?? '';
    if (last.isNotEmpty) {
      facts.add('Last use ${formatToolLastUse(last)}');
    }
    return facts;
  }

  String _memberText(SceneObject frame, String prop) {
    for (final object in widget.store.document.objects) {
      if (!kitChildBelongsToFrame(object, frame)) {
        continue;
      }
      final value = object.props[prop]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return frame.props[prop]?.toString().trim() ?? '';
  }

  SceneObject? _linkedRepository(SceneObject toolFrame) {
    for (final repository in repositoryFrames(widget.store.document)) {
      if (kitHasLink(repository, to: toolFrame.id, port: repositoryPort)) {
        return repository;
      }
    }
    return null;
  }

  String _repositoryAvailability(SceneObject? repository) {
    final path = repository?.props[repositoryPathProp]?.toString().trim() ?? '';
    if (repository == null) {
      return 'Needs repository';
    }
    if (path.isEmpty) {
      return 'Folder not chosen';
    }
    return 'Available';
  }

  Widget _portHeading(String label) {
    final tokens = PaintScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: tokens.muted, letterSpacing: 0.3),
      ),
    );
  }

  Widget _connectionRow({
    required SceneObject kit,
    required bool connected,
    required VoidCallback onTap,
    String? keyId,
    String? detail,
  }) {
    final tokens = PaintScope.of(context);
    final frame =
        kitFrameForSelection(
          document: widget.store.document,
          selectedId: kit.id,
        ) ??
        kit;
    final name = kitDisplayName(widget.store.document, kit);
    final facts = _connectionFacts(frame);
    final color = kitAccentColor(frame);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PaintHover(
        child: GestureDetector(
          key: ValueKey('allowed-connection-${keyId ?? kit.id}'),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PaintTokens.radiusField),
              border: Border.all(
                color: connected ? color : tokens.hairline,
                width: connected ? 1.4 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (facts.isNotEmpty)
                          Text(
                            facts.join(' · '),
                            key: ValueKey(
                              'connection-facts-${keyId ?? kit.id}',
                            ),
                            style: TextStyle(color: tokens.muted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  if (detail != null) ...[
                    Text(
                      detail,
                      style: TextStyle(color: tokens.muted, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (connected)
                    Text(
                      'Connected',
                      style: TextStyle(color: tokens.muted, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final tokens = PaintScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(color: tokens.hairline, child: const SizedBox(height: 1)),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: tokens.muted, letterSpacing: 0.4),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _typeFields(SceneObject object) {
    switch (object.type) {
      case boxTypeId:
        return [
          _field(
            key: const Key('inspector-fill'),
            label: 'Fill',
            controller: _fill,
            onChanged: (value) => _applyAppearance({'fill': value}),
            onSubmitted: (value) =>
                _applyAppearance({'fill': value}, immediate: true),
          ),
        ];
      case textTypeId:
        return [
          _field(
            key: const Key('inspector-content'),
            label: 'Content',
            controller: _content,
            focusNode: _contentFocus,
            onChanged: (value) => _applyProps({'content': value}),
            onSubmitted: (value) =>
                _applyProps({'content': value}, immediate: true),
          ),
          _field(
            label: 'Font size',
            controller: _fontSize,
            onSubmitted: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) {
                _applyProps({'fontSize': parsed}, immediate: true);
              }
            },
          ),
          _field(
            label: 'Color',
            controller: _color,
            onChanged: (value) => _applyProps({'color': value}),
            onSubmitted: (value) =>
                _applyProps({'color': value}, immediate: true),
          ),
        ];
      case buttonTypeId:
        return [
          _field(
            label: 'Label',
            controller: _label,
            onChanged: (value) => _applyProps({'label': value}),
            onSubmitted: (value) =>
                _applyProps({'label': value}, immediate: true),
          ),
        ];
      default:
        if (object.props.isEmpty) {
          return const [];
        }
        return [
          Text('Props', style: Theme.of(context).textTheme.labelSmall),
          for (final entry in object.props.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.key}: ${entry.value}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ];
    }
  }

  Widget _readOnly(
    String label,
    String value, {
    bool mono = false,
    bool hideLabel = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideLabel && label.isNotEmpty)
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono
                ? Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace')
                : Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _field({
    Key? key,
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PaintTextField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        label: label,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}
