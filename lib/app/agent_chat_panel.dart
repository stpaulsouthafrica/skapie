import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/paint/paint.dart';

/// Bottom chat strip. Vanilla on-ramp: [AgentController.sendUser] then an LLM kit.
/// The widget never touches KitApi.
class AgentChatPanel extends StatefulWidget {
  const AgentChatPanel({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final AgentController controller;
  final VoidCallback onOpenSettings;

  @override
  State<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends State<AgentChatPanel> {
  final _input = TextEditingController();
  StreamSubscription<AgentEvent>? _events;
  var _busy = false;
  AgentSession? _listening;

  AgentSession get _session => widget.controller.session;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _listen(_session);
  }

  @override
  void didUpdateWidget(AgentChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _listen(_session);
    }
  }

  void _onController() {
    if (!mounted) {
      return;
    }
    if (_listening != widget.controller.session) {
      _listen(widget.controller.session);
    }
    setState(() {});
  }

  void _listen(AgentSession session) {
    _events?.cancel();
    _listening = session;
    _events = session.events.listen((event) {
      if (!mounted) {
        return;
      }
      if (event is AgentTurnFinished || event is AgentTurnFailed) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _events?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) {
      return;
    }
    if (text == '/settings' || text == '/settings/') {
      _input.clear();
      widget.onOpenSettings();
      return;
    }
    _input.clear();
    setState(() => _busy = true);
    try {
      await widget.controller.sendUser(text);
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
        key: const Key('agent-chat-input'),
        controller: _input,
        hint: 'Message',
        enabled: !_busy,
        onSubmitted: (_) => _send(),
      ),
    );
  }
}
