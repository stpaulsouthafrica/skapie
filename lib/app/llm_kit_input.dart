import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';
import 'package:skapie/scene/scene.dart';

/// Selection-scoped prompt field for a compound LLM kit. Enter runs vanilla.
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
  final _input = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  var _busy = false;
  String? _boundId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _bind(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(LlmKitInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    if (oldWidget.body.id != widget.body.id) {
      _bind(force: true);
      _focus.requestFocus();
    } else if (!_focus.hasFocus && !_busy) {
      _bind(force: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) {
      setState(() {});
    }
  }

  void _bind({required bool force}) {
    if (!force && _boundId == widget.body.id) {
      return;
    }
    _boundId = widget.body.id;
    final prompt = widget.body.props['prompt']?.toString() ?? '';
    if (_input.text != prompt) {
      _input.value = TextEditingValue(
        text: prompt,
        selection: TextSelection.collapsed(offset: prompt.length),
      );
    }
  }

  void _commitPrompt(String text) {
    setLlmKitPrompt(
      kitApi: widget.kitApi,
      bodyId: widget.body.id,
      prompt: text,
    );
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _commitPrompt(text);
    });
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
    final prompt = widget.body.props['prompt']?.toString() ?? _input.text;
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

  Future<void> _submit(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || _busy) {
      return;
    }
    _debounce?.cancel();
    _commitPrompt(prompt);
    setState(() => _busy = true);
    try {
      await widget.controller.sendUser(prompt, targetBodyId: widget.body.id);
    } catch (_) {
      // Failure is visible on the LLM kit.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final needsInput = _input.text.trim().isEmpty;
    final choices = _choices;
    final selected = _selectedModel;
    return PaintPanel(
      capsule: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
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
          const SizedBox(height: 8),
          PaintTextField(
            key: const Key('llm-kit-input'),
            controller: _input,
            focusNode: _focus,
            autofocus: true,
            hint: 'Input',
            label: 'Input',
            enabled: !_busy,
            onChanged: _onChanged,
            onSubmitted: _submit,
          ),
          if (needsInput)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Needs input',
                style: TextStyle(color: tokens.muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
