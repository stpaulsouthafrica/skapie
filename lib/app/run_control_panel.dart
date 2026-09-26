import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

/// Settings and controls live on the visible kit. No tool is attached here.
class RunControlPanel extends StatelessWidget {
  const RunControlPanel({
    super.key,
    required this.frame,
    required this.kitApi,
    required this.controller,
  });

  final SceneObject frame;
  final KitApi kitApi;
  final AgentController controller;

  String? get targetBodyId {
    for (final link in kitLinksOf(frame)) {
      if (link.port == runControlPort &&
          kitApi.store.document.objectById(link.to) != null) {
        return link.to;
      }
    }
    return null;
  }

  void _setLimit(String key, String raw, int maximum) {
    final value = int.tryParse(raw.trim());
    if (value == null || value < 0) return;
    kitApi.updateProps(frame.id, {key: value.clamp(0, maximum)});
    _refreshCard();
  }

  void _refreshCard() {
    final current = kitApi.store.document.objectById(frame.id);
    if (current == null) return;
    final body =
        (kitMembers(document: kitApi.store.document, selectedId: frame.id) ??
                const <SceneObject>[])
            .where((item) => item.props[skapieRoleProp] == 'body')
            .firstOrNull;
    if (body == null) return;
    kitApi.updateProps(body.id, {
      'content':
          '${current.props['modelTurns']} turns · '
          '${current.props['toolCalls']} tools · '
          '${current.props['elapsedSeconds']}s\n'
          'Failed check: ${current.props['failedCheckRule'] == 'oneMoreTurn' ? 'one more turn' : 'off'}',
    });
  }

  Widget _limit(String key, String label, String help, int maximum) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Tooltip(
      message: '$help Set to 0 to disable this limit.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('run-control-$key-${frame.props[key]}'),
            initialValue: '${frame.props[key]}',
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onFieldSubmitted: (value) => _setLimit(key, value, maximum),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final target = targetBodyId;
    final runningHere = target != null && controller.runningBodyId == target;
    final prompt = target == null
        ? ''
        : llmCableInput(kitApi.store.document, target).trim();
    final blocked =
        target != null &&
        validateBoard(kitApi.store.document)
            .runBlockers(target)
            .any((issue) => issue.kind != BoardIssueKind.missingGrant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (target == null) ...[
          const Text('Cable an LLM to start a run'),
          const SizedBox(height: 12),
        ],
        _limit('modelTurns', 'Model turns', 'Maximum model requests.', 100),
        _limit('toolCalls', 'Tool calls', 'Maximum tool calls.', 500),
        _limit('elapsedSeconds', 'Elapsed seconds', 'Maximum run time.', 3600),
        _limit(
          'outputChars',
          'Output characters',
          'Maximum generated text and tool output.',
          1000000,
        ),
        Tooltip(
          message: 'Allow one extra model turn after a cabled failed check.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Failed check rule', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey(
                  'run-control-rule-${frame.props['failedCheckRule']}',
                ),
                initialValue: frame.props['failedCheckRule'] == 'oneMoreTurn'
                    ? 'oneMoreTurn'
                    : 'off',
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'off', child: Text('Off')),
                  DropdownMenuItem(
                    value: 'oneMoreTurn',
                    child: Text('Allow one more turn'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    kitApi.updateProps(frame.id, {'failedCheckRule': value});
                    _refreshCard();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (runningHere)
          Row(
            children: [
              TextButton(
                key: const Key('run-control-pause'),
                onPressed: controller.pauseRun,
                child: const Text('Pause'),
              ),
              TextButton(
                key: const Key('run-control-stop'),
                onPressed: controller.interruptRun,
                child: const Text('Stop'),
              ),
            ],
          )
        else
          FilledButton(
            key: const Key('run-control-start'),
            onPressed:
                target == null ||
                    prompt.isEmpty ||
                    blocked ||
                    controller.runningBodyId != null
                ? null
                : () => controller
                      .sendUser(prompt, targetBodyId: target)
                      .catchError((Object _) {}),
            child: const Text('Start'),
          ),
      ],
    );
  }
}
