import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/run_control.dart';
import 'package:skapie/agent/run_ledger.dart';

class RunRail extends StatefulWidget {
  const RunRail({super.key, required this.bodyId, required this.controller});

  final String bodyId;
  final AgentController controller;

  @override
  State<RunRail> createState() => _RunRailState();
}

class _RunRailState extends State<RunRail> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.runningBodyId == widget.bodyId) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final active = controller.runningBodyId == widget.bodyId;
    final run = controller.latestRunFor(widget.bodyId);
    final limits = active
        ? controller.activeLimits
        : runLimitsFor(controller.kitApi.store.document, widget.bodyId);
    final turns = active
        ? controller.modelTurnsUsed
        : run?.events
                      .where((event) => event.kind == RunEventKind.stateChanged)
                      .lastOrNull
                      ?.payload['modelTurns']
                  as int? ??
              0;
    final calls = active
        ? controller.toolCallsUsed
        : run?.events
                      .where((event) => event.kind == RunEventKind.stateChanged)
                      .lastOrNull
                      ?.payload['toolCalls']
                  as int? ??
              0;
    final chars = active
        ? controller.outputCharsUsed
        : run?.events
                      .where((event) => event.kind == RunEventKind.stateChanged)
                      .lastOrNull
                      ?.payload['outputChars']
                  as int? ??
              0;
    final elapsed = active
        ? controller.runElapsed
        : run == null || run.events.length < 2
        ? Duration.zero
        : run.events.last.at.difference(run.events.first.at);
    final remaining = limits.elapsed - elapsed;
    final state = active
        ? switch (controller.runPhase) {
            RunPhase.validating => 'Validating',
            RunPhase.assembling => 'Preparing request',
            RunPhase.modelWait => 'Waiting for model',
            RunPhase.toolWait => 'Using a tool',
            RunPhase.cancelling => 'Stopping',
            _ => controller.runPhase.name,
          }
        : run?.status.name ?? 'Ready';
    final stop = run?.events.reversed
        .where((event) => event.kind == RunEventKind.runFailed)
        .firstOrNull;
    final reason = stop?.payload['limit'] ?? stop?.payload['category'];
    return Text(
      '$state · turn $turns/${limits.effectiveModelTurns} · '
      'tools $calls/${limits.toolCalls} · '
      '${(limits.outputChars - chars).clamp(0, limits.outputChars)} chars left · '
      '${elapsed.inSeconds}s elapsed · '
      '${remaining.inSeconds.clamp(0, limits.elapsed.inSeconds)}s left'
      '${reason == null ? '' : ' · $reason'}',
      key: const Key('run-rail'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
