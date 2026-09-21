import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent.dart';

/// Overlay chat. Calls [AgentSession.sendUser] only — never KitApi.
class AgentChatPanel extends StatefulWidget {
  const AgentChatPanel({super.key, required this.session});

  final AgentSession session;

  @override
  State<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends State<AgentChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<AgentEvent>? _events;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listen(widget.session);
  }

  @override
  void didUpdateWidget(AgentChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _events?.cancel();
      _listen(widget.session);
    }
  }

  void _listen(AgentSession session) {
    _events = session.events.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (event is AgentTurnFailed) {
          _error = event.error.toString();
        }
        if (event is AgentTurnFinished) {
          _error = null;
        }
      });
      _jumpToEnd();
    });
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) {
      return;
    }
    _input.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.sendUser(text);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visible = [
      for (final message in widget.session.messages)
        if (message.role != AgentRole.system) message,
    ];

    return Material(
      elevation: 6,
      color: colors.surfaceContainerHighest,
      shadowColor: colors.shadow,
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Text('Chat', style: textTheme.labelLarge),
                  const Spacer(),
                  if (_busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final message = visible[index];
                  final body = _bodyFor(message);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _labelFor(message.role),
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          body,
                          style: textTheme.bodySmall?.copyWith(
                            color: message.role == AgentRole.tool
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(color: colors.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('agent-chat-input'),
                      controller: _input,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    key: const Key('agent-chat-send'),
                    tooltip: 'Send',
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _labelFor(AgentRole role) {
    return switch (role) {
      AgentRole.system => 'System',
      AgentRole.user => 'You',
      AgentRole.assistant => 'Agent',
      AgentRole.tool => 'Tool',
    };
  }

  String _bodyFor(AgentMessage message) {
    switch (message.role) {
      case AgentRole.system:
      case AgentRole.user:
        return message.content;
      case AgentRole.assistant:
        if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
          return [
            for (final call in message.toolCalls!)
              '${call.name} ${call.argumentsJson}',
          ].join('\n');
        }
        return message.content;
      case AgentRole.tool:
        final body = message.content;
        return body.length > 140 ? '${body.substring(0, 140)}…' : body;
    }
  }
}
