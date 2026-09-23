import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/connection_info.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';

/// What a selected cable is for, what it carries, and whether it just ran.
class ConnectionInspector extends StatelessWidget {
  const ConnectionInspector({
    super.key,
    required this.kitApi,
    required this.selection,
    required this.cableId,
    this.controller,
    this.onCut,
  });

  final KitApi kitApi;
  final SelectionController selection;
  final String cableId;
  final AgentController? controller;

  /// Plays the board retraction. Absent callers disconnect immediately.
  final ValueChanged<SceneCable>? onCut;

  SceneCable? _cable(BoardValidation validation) {
    for (final cable in [
      ...sceneCables(kitApi.store.document),
      ...validation.extraCables,
    ]) {
      if (cable.id == cableId) {
        return cable;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final document = kitApi.store.document;
    final validation = validateBoard(document);
    final cable = _cable(validation);
    if (cable == null) {
      return const SizedBox.shrink();
    }
    final tokens = PaintScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final info = describeConnection(document, cable, validation: validation);
    final lastUse = lastUseSummary(
      document,
      cable,
      controller?.lastRunUse ?? const {},
    );
    final carries = switch (info.role) {
      PortRole.data => 'Carries now',
      PortRole.capability => 'Offers',
      PortRole.grant => 'Grants',
    };
    Widget section(String title, List<Widget> children) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: tokens.hairline,
              child: const SizedBox(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Text(
                title,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.muted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            ...children,
          ],
        ),
      );
    }

    Widget line(String text, {Key? key, Color? color, int maxLines = 2}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          key: key,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(color: color ?? tokens.ink),
        ),
      );
    }

    return Material(
      key: const Key('connection-inspector'),
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
                    Text('Connection', style: textTheme.labelLarge),
                    section('From → To', [
                      line(info.source, key: const Key('connection-source')),
                      line(
                        info.destination,
                        key: const Key('connection-destination'),
                      ),
                    ]),
                    section('Role', [
                      line(info.roleLabel, key: const Key('connection-role')),
                      line(info.role.meaning, color: tokens.muted),
                    ]),
                    section(carries, [
                      line(
                        info.preview.isEmpty ? '—' : info.preview,
                        key: const Key('connection-preview'),
                        maxLines: 8,
                      ),
                    ]),
                    section('Last use', [
                      line(lastUse, key: const Key('connection-last-use')),
                    ]),
                    if (info.issue != null)
                      section('Problem', [
                        line(
                          info.issue!,
                          key: const Key('connection-issue'),
                          color: tokens.danger,
                        ),
                      ]),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: const Key('connection-cut'),
                    child: PaintButton(
                      label: 'Cut cable',
                      onPressed: () {
                        final cut = onCut;
                        if (cut != null) {
                          cut(cable);
                          return;
                        }
                        selection.selectCable(null);
                        disconnectSceneCable(kitApi: kitApi, cable: cable);
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'On the board: Delete cuts, [ and ] step through cables.',
                    style: textTheme.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
