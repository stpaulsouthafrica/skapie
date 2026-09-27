import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/paint/paint.dart';

/// Concise banner for runs left unfinished by a quit. Continue, Inspect, or
/// End. Nothing resumes on its own; the user always chooses.
class RunRecoveryBanner extends StatelessWidget {
  const RunRecoveryBanner({
    super.key,
    required this.controller,
    required this.onInspect,
  });

  final AgentController controller;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) {
    final notices = controller.pendingRecovery;
    if (notices.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = PaintScope.of(context);
    return Column(
      key: const Key('run-recovery-banner'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notice in notices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: notice.uncertain
                      ? tokens.danger.withValues(alpha: 0.5)
                      : tokens.hairline,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.uncertain
                          ? 'Run interrupted · effect uncertain'
                          : 'Run interrupted',
                      style: TextStyle(
                        color: notice.uncertain ? tokens.danger : tokens.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${notice.runId} · ${notice.bodyId}',
                      style: TextStyle(color: tokens.muted, fontSize: 11),
                    ),
                    if (notice.uncertain)
                      Text(
                        'Inspect before you retry.',
                        style: TextStyle(color: tokens.muted, fontSize: 11),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (notice.canContinue)
                          TextButton(
                            key: const Key('run-recovery-continue'),
                            onPressed: () => controller.resumeRun(
                              notice.bodyId,
                              fromRunId: notice.runId,
                            ),
                            child: Text(
                              'Continue',
                              style: TextStyle(color: tokens.accent),
                            ),
                          ),
                        TextButton(
                          key: const Key('run-recovery-inspect'),
                          onPressed: () => onInspect(notice.bodyId),
                          child: Text(
                            'Inspect',
                            style: TextStyle(color: tokens.accent),
                          ),
                        ),
                        TextButton(
                          key: const Key('run-recovery-end'),
                          onPressed: () => controller.endRun(notice.runId),
                          child: Text(
                            'End',
                            style: TextStyle(color: tokens.muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
