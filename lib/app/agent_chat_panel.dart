import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/app/agent_settings_panel.dart';

const List<String> agentEmptyPrompts = [
  'Add a box near the center',
  'Instantiate the demo note kit',
  'List kits',
];

/// Overlay chat. Calls [AgentSession.sendUser] only — never KitApi.
class AgentChatPanel extends StatefulWidget {
  const AgentChatPanel({super.key, required this.controller});

  final AgentController controller;

  @override
  State<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends State<AgentChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<AgentEvent>? _events;
  var _busy = false;
  var _settingsOpen = false;
  String? _error;
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
    widget.controller.removeListener(_onController);
    _events?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) {
      return;
    }
    _input.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.sendUser(text);
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
      for (final message in _session.messages)
        if (message.role != AgentRole.system) message,
    ];
    final empty = visible.isEmpty;
    final chip = widget.controller.statusChip;
    final fake = widget.controller.runtime.useFake;
    final errorText = _error ?? widget.controller.runtime.warning;

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
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
              child: Row(
                children: [
                  Text('Chat', style: textTheme.labelLarge),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: fake
                              ? colors.surfaceContainerHigh
                              : colors.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          chip,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Agent settings',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: () =>
                        setState(() => _settingsOpen = !_settingsOpen),
                    icon: Icon(
                      _settingsOpen ? Icons.close : Icons.settings_outlined,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _settingsOpen
                  ? AgentSettingsPanel(
                      controller: widget.controller,
                      onClose: () => setState(() => _settingsOpen = false),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: empty
                              ? _EmptyState(
                                  fake: fake,
                                  chip: chip,
                                  onPrompt: (prompt) {
                                    _input.text = prompt;
                                    _input.selection = TextSelection.collapsed(
                                      offset: prompt.length,
                                    );
                                  },
                                )
                              : ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final message = visible[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _labelFor(message.role),
                                            style: textTheme.labelSmall
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          ),
                                          Text(
                                            _bodyFor(message),
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      message.role ==
                                                          AgentRole.tool
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
                        if (errorText != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                            child: Text(
                              errorText,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.error,
                              ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.fake,
    required this.chip,
    required this.onPrompt,
  });

  final bool fake;
  final String chip;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final line = fake
        ? 'You\'re on Fake — replies Echo. Open settings to use a live model.'
        : 'Live $chip. Ask in plain English; kit tools change the canvas.';

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      children: [
        Text(line, style: textTheme.bodySmall),
        const SizedBox(height: 12),
        Text('Try:', style: textTheme.labelSmall),
        const SizedBox(height: 6),
        for (final prompt in agentEmptyPrompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                label: Text(prompt, style: textTheme.bodySmall),
                backgroundColor: colors.surface,
                onPressed: () => onPrompt(prompt),
              ),
            ),
          ),
      ],
    );
  }
}
