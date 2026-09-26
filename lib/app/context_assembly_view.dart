import 'package:flutter/material.dart';
import 'package:skapie/agent/context_assembly.dart';
import 'package:skapie/app/full_screen_text_editor.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene.dart';

/// Collapsible view of exactly what the model will see, and why.
class ContextAssemblyView extends StatefulWidget {
  const ContextAssemblyView({
    super.key,
    required this.body,
    required this.kitApi,
  });

  final SceneObject body;
  final KitApi kitApi;

  @override
  State<ContextAssemblyView> createState() => _ContextAssemblyViewState();
}

class _ContextAssemblyViewState extends State<ContextAssemblyView> {
  var _expanded = false;

  ContextAssembly _assembly() {
    return assembleContext(
      kitApi: widget.kitApi,
      llmBodyId: widget.body.id,
      taskInput: llmCableInput(widget.kitApi.store.document, widget.body.id),
    );
  }

  Future<void> _openFull(String text) {
    return showFullScreenTextEditor(
      context: context,
      title: 'Context assembly',
      text: text,
      readOnly: true,
      syntax: EditorSyntax.request,
      surfaceKey: const Key('context-assembly-fullscreen'),
      closeKey: const Key('context-assembly-close'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final assembly = _assembly();
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
                key: const Key('context-assembly-search'),
                tooltip: 'Full screen',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () => _openFull(formatContextAssembly(assembly)),
                icon: Icon(Icons.search, size: 16, color: tokens.muted),
              ),
              IconButton(
                key: const Key('context-assembly-toggle'),
                tooltip: _expanded ? 'Collapse' : 'Expand',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: tokens.muted,
                ),
              ),
            ],
          ),
          if (_expanded)
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tokens.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  key: const Key('context-assembly'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final layer in ContextLayer.values)
                      ..._layer(tokens, assembly, layer),
                    if (assembly.exclusions.isNotEmpty)
                      ..._exclusions(tokens, assembly),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _layer(
    PaintTokens tokens,
    ContextAssembly assembly,
    ContextLayer layer,
  ) {
    final items = assembly.itemsFor(layer);
    if (items.isEmpty) {
      return const [];
    }
    return [
      Padding(
        key: Key('context-layer-${layer.name}'),
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          layer.label,
          style: TextStyle(
            color: tokens.muted,
            fontSize: 11,
            letterSpacing: 0.4,
          ),
        ),
      ),
      for (final item in items)
        Padding(
          key: Key('context-item-${item.order}'),
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.order}. ${item.sourceRange}'
                ' · ${item.provenance.label}'
                '${item.truncated ? ' · Truncated' : ''}',
                style: TextStyle(color: tokens.ink, fontSize: 12),
              ),
              Text(
                item.reason,
                style: TextStyle(color: tokens.muted, fontSize: 11),
              ),
              Text(
                item.provenance.trust,
                style: TextStyle(color: tokens.muted, fontSize: 11),
              ),
              if (_preview(item.text).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _preview(item.text),
                    style: TextStyle(
                      color: tokens.muted,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _exclusions(PaintTokens tokens, ContextAssembly assembly) {    return [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          'Excluded',
          style: TextStyle(
            color: tokens.muted,
            fontSize: 11,
            letterSpacing: 0.4,
          ),
        ),
      ),
      for (final exclusion in assembly.exclusions)
        Padding(
          key: Key('context-exclusion-${exclusion.sourceKitId}'),
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exclusion.sourceKitId,
                style: TextStyle(color: tokens.ink, fontSize: 12),
              ),
              Text(
                exclusion.reason,
                style: TextStyle(color: tokens.muted, fontSize: 11),
              ),
            ],
          ),
        ),
    ];
  }
}

String _preview(String text) {
  final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (line.length <= 100) {
    return line;
  }
  return '${line.substring(0, 100)}...';
}
