import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
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
    if (oldWidget.body.id != widget.body.id) {
      _bind(force: true);
      _focus.requestFocus();
    } else if (!_focus.hasFocus && !_busy) {
      _bind(force: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _bind({required bool force}) {
    if (!force && _boundId == widget.body.id) {
      return;
    }
    _boundId = widget.body.id;
    final prompt = widget.body.props['prompt']?.toString() ?? '';
    if (_input.text != prompt) {
      _input.text = prompt;
      _input.selection = TextSelection.collapsed(offset: prompt.length);
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
    return PaintPanel(
      capsule: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: PaintTextField(
        key: const Key('llm-kit-input'),
        controller: _input,
        focusNode: _focus,
        autofocus: true,
        hint: 'Prompt',
        enabled: !_busy,
        onChanged: _onChanged,
        onSubmitted: _submit,
      ),
    );
  }
}
