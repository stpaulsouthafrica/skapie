import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';
import 'package:skapie/scene/scene.dart';

/// Inspector-hosted model and run for a compound LLM kit.
/// The prompt is the text cabled into Input.
class LlmKitInput extends StatefulWidget {
  const LlmKitInput({
    super.key,
    required this.body,
    required this.kitApi,
    required this.controller,
  });

  final SceneObject body;
  final KitApi kitApi;
  final AgentController controller;

  @override
  State<LlmKitInput> createState() => _LlmKitInputState();
}

class _LlmKitInputState extends State<LlmKitInput> {
  var _busy = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(LlmKitInput oldWidget) {
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

  List<AgentModelInfo> get _choices {
    final choices = widget.controller.kitModelChoices;
    final selected = widget.body.props['model']?.toString().trim() ?? '';
    if (selected.isEmpty || choices.any((model) => model.id == selected)) {
      return choices;
    }
    return [AgentModelInfo(id: selected, displayName: selected), ...choices];
  }

  String? get _selectedModel {
    final selected = widget.body.props['model']?.toString().trim() ?? '';
    if (selected.isEmpty) {
      return null;
    }
    for (final model in _choices) {
      if (model.id == selected) {
        return selected;
      }
    }
    return null;
  }

  void _onModel(String? id) {
    if (id == null) {
      return;
    }
    AgentModelInfo? info;
    for (final model in _choices) {
      if (model.id == id) {
        info = model;
        break;
      }
    }
    if (info == null) {
      return;
    }
    final runtime = widget.controller.runtime;
    final provider = runtime.useFake || runtime.presetId == 'fake'
        ? 'opencode-go'
        : runtime.presetId;
    final surface =
        info.surface?.id ?? lookupOpenCodeGoModel(info.id)?.surface.id ?? '';
    final prompt = _cableInput;
    widget.kitApi.updateProps(widget.body.id, {
      'provider': provider,
      'model': info.id,
      'surface': surface,
      'content': formatLlmKitContent(
        prompt: prompt,
        reply: widget.body.props['reply']?.toString(),
        error: widget.body.props['error']?.toString(),
        model: info.id,
        surface: surface,
        attachedTools: llmAttachedToolNames(
          widget.kitApi.store.document,
          widget.body.id,
        ),
      ),
    });
  }

  String get _cableInput =>
      llmCableInput(widget.kitApi.store.document, widget.body.id).trim();

  List<BoardIssue> get _blockers =>
      validateBoard(widget.kitApi.store.document).runBlockers(widget.body.id);

  void _stop() {
    widget.controller.interruptRun();
  }

  Future<void> _submit() async {
    final prompt = _cableInput;
    if (_blockers.isNotEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.sendUser(prompt, targetBodyId: widget.body.id);
    } catch (_) {
      // Failure is written onto a text kit cabled from Output.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final blockers = _blockers;
    final runningHere = widget.controller.runningBodyId == widget.body.id;
    final blocked = blockers.isNotEmpty || (_busy && !runningHere);
    final choices = _choices;
    final selected = _selectedModel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: ValueKey('llm-model-${choices.length}-$selected'),
          child: DropdownButtonFormField<String>(
            key: const Key('llm-kit-model'),
            initialValue: selected,
            isExpanded: true,
            menuMaxHeight: 240,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
            hint: const Text('Model'),
            items: [
              for (final model in choices)
                DropdownMenuItem(
                  value: model.id,
                  child: Text(
                    model.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy ? null : _onModel,
          ),
        ),
        for (final (index, issue) in blockers.indexed)
          Padding(
            key: ValueKey('llm-kit-run-blocker-$index'),
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              issue.message,
              style: TextStyle(color: tokens.danger, fontSize: 11),
            ),
          ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const Key('llm-kit-run'),
          child: PaintButton(
            label: runningHere ? 'Stop' : 'Run',
            onPressed: runningHere ? _stop : (blocked ? null : _submit),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
