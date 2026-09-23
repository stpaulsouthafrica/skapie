import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/llm_request_preview.dart';
import 'package:skapie/app/llm_request_highlight.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

/// Collapsible preview of the request Run will send for the selected LLM kit.
class LlmRequestInformation extends StatefulWidget {
  const LlmRequestInformation({
    super.key,
    required this.body,
    required this.kitApi,
    required this.controller,
  });

  final SceneObject body;
  final KitApi kitApi;
  final AgentController controller;

  @override
  State<LlmRequestInformation> createState() => _LlmRequestInformationState();
}

class _LlmRequestInformationState extends State<LlmRequestInformation> {
  var _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(LlmRequestInformation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (mounted) {
      setState(() {});
    }
  }

  String _text() {
    final prompt = llmCableInput(
      widget.kitApi.store.document,
      widget.body.id,
    ).trim();
    final document = widget.kitApi.store.document;
    final runtime = widget.controller.runtime;
    return formatLlmRequestPreview(
      prompt: prompt,
      systemText: llmContextText(document, widget.body.id),
      history: llmConversationHistory(document, widget.body.id),
      useFake: runtime.useFake,
      sessionModel: widget.controller.session.model,
      attachedTools: worldToolsForLlm(
        kitApi: widget.kitApi,
        llmBodyId: widget.body.id,
      ),
      presetId: runtime.presetId,
      baseUrl: runtime.baseUrl,
      apiKey: runtime.apiKey,
      runtimeModel: runtime.model,
      kitModel: widget.body.props['model']?.toString() ?? '',
      kitProvider: widget.body.props['provider']?.toString() ?? '',
      sessionId: widget.controller.session.id,
    );
  }

  Future<void> _openFull(String text) {
    final tokens = PaintScope.of(context);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close request',
      barrierColor: const Color(0xE60C0C0E),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _RequestFullscreen(text: text, tokens: tokens);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final text = _text();
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
                  child: Text('Request Information', style: label),
                ),
              ),
              IconButton(
                key: const Key('llm-request-expand'),
                tooltip: 'Full screen',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () => _openFull(text),
                icon: Icon(Icons.search, size: 16, color: tokens.muted),
              ),
              IconButton(
                key: const Key('llm-request-toggle'),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tokens.hairline),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText.rich(
                    highlightLlmRequest(text, tokens),
                    key: const Key('llm-request-information'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestFullscreen extends StatelessWidget {
  const _RequestFullscreen({required this.text, required this.tokens});

  final String text;
  final PaintTokens tokens;

  @override
  Widget build(BuildContext context) {
    final span = highlightLlmRequest(text, tokens, fontSize: 13);
    return Material(
      key: const Key('llm-request-fullscreen'),
      color: tokens.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Request',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: tokens.ink),
                    ),
                  ),
                  IconButton(
                    key: const Key('llm-request-close'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: tokens.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.panel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.hairline),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText.rich(span),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
