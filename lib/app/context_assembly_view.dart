import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/app/full_screen_text_editor.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene.dart';

/// The sources for the next model request, and why. The magnifying glass opens
/// the whole thing in the Full Screen editor. There is no expand chevron;
/// inspector previews open full screen only.
class ContextAssemblyView extends StatelessWidget {
  const ContextAssemblyView({
    super.key,
    required this.body,
    required this.kitApi,
    this.controller,
  });

  final SceneObject body;
  final KitApi kitApi;
  final AgentController? controller;

  ContextAssembly _assembly() {
    return assembleContext(
      kitApi: kitApi,
      llmBodyId: body.id,
      taskInput: llmCableInput(kitApi.store.document, body.id),
      excerpts: controller?.excerptsFor(body.id) ?? const [],
    );
  }

  Future<void> _openFull(BuildContext context) {
    return showFullScreenTextEditor(
      context: context,
      title: 'Context assembly',
      text: formatContextAssembly(_assembly()),
      readOnly: true,
      syntax: EditorSyntax.context,
      surfaceKey: const Key('context-assembly-fullscreen'),
      closeKey: const Key('context-assembly-close'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final label = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: tokens.muted, letterSpacing: 0.4);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(color: tokens.hairline, child: const SizedBox(height: 1)),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Text('Context Assembly', style: label),
                ),
              ),
              IconButton(
                key: const Key('context-assembly-expand'),
                tooltip: 'Full screen',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () => _openFull(context),
                icon: Icon(Icons.search, size: 16, color: tokens.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
