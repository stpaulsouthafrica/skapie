import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';

const List<String> agentProviderChoices = [
  'fake',
  'opencode-go',
  'openrouter',
  'openai',
  'custom',
];

/// Gear-panel form. Apply rebuilds the session; Cancel leaves it unchanged.
class AgentSettingsPanel extends StatefulWidget {
  const AgentSettingsPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final AgentController controller;
  final VoidCallback onClose;

  @override
  State<AgentSettingsPanel> createState() => _AgentSettingsPanelState();
}

class _AgentSettingsPanelState extends State<AgentSettingsPanel> {
  late String _provider;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = widget.controller.runtime;
    final prefs = widget.controller.prefs;
    _provider =
        prefs?.providerId ?? (runtime.useFake ? 'fake' : runtime.presetId);
    if (!agentProviderChoices.contains(_provider)) {
      _provider = 'fake';
    }
    _model = TextEditingController(text: prefs?.model ?? runtime.model ?? '');
    _apiKey = TextEditingController();
    _baseUrl = TextEditingController(
      text:
          prefs?.baseUrl ??
          (runtime.presetId == 'custom' ? runtime.baseUrl ?? '' : ''),
    );
  }

  @override
  void dispose() {
    _model.dispose();
    _apiKey.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _apply({required bool fake}) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (fake) {
        await widget.controller.useFake();
      } else {
        await widget.controller.applySettings(
          providerId: _provider,
          model: _model.text,
          apiKey: _apiKey.text,
          baseUrl: _baseUrl.text,
        );
      }
      if (mounted) {
        widget.onClose();
      }
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
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Agent settings', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('agent-settings-provider'),
            initialValue: _provider,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Provider',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final id in agentProviderChoices)
                DropdownMenuItem(value: id, child: Text(id)),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _provider = value);
                  },
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('agent-settings-model'),
            controller: _model,
            enabled: !_busy && _provider != 'fake',
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Model',
              hintText: 'kimi-k2.6',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('agent-settings-api-key'),
            controller: _apiKey,
            enabled: !_busy && _provider != 'fake',
            obscureText: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'API key',
              hintText: 'Not saved to disk',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('agent-settings-base-url'),
            controller: _baseUrl,
            enabled: !_busy && _provider != 'fake',
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Base URL',
              hintText: _provider == 'custom'
                  ? 'Required for custom'
                  : 'Optional override',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          const Spacer(),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                key: const Key('agent-settings-cancel'),
                onPressed: _busy ? null : widget.onClose,
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('agent-settings-fake'),
                onPressed: _busy ? null : () => _apply(fake: true),
                child: const Text('Use Fake'),
              ),
              FilledButton(
                key: const Key('agent-settings-apply'),
                onPressed: _busy ? null : () => _apply(fake: false),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
