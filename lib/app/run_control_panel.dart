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
    if (value == null || value < 1) return;
    kitApi.updateProps(frame.id, {key: value.clamp(1, maximum)});
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

  Widget _limit(String key, String label, int maximum) => TextFormField(
    key: ValueKey('run-control-$key-${frame.props[key]}'),
    initialValue: '${frame.props[key]}',
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, isDense: true),
    onFieldSubmitted: (value) => _setLimit(key, value, maximum),
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
        Text(
          target == null ? 'Cable LLM to start a run' : 'Controls cabled LLM',
        ),
        _limit('modelTurns', 'Model turns', 100),
        _limit('toolCalls', 'Tool calls', 500),
        _limit('elapsedSeconds', 'Elapsed seconds', 3600),
        _limit('outputChars', 'Output characters', 1000000),
        DropdownButtonFormField<String>(
          key: ValueKey('run-control-rule-${frame.props['failedCheckRule']}'),
          initialValue: frame.props['failedCheckRule'] == 'oneMoreTurn'
              ? 'oneMoreTurn'
              : 'off',
          decoration: const InputDecoration(labelText: 'Failed check rule'),
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
        const SizedBox(height: 8),
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
