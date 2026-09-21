import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/agent/agent_provider.dart';

const List<String> agentProviderChoices = [
  'fake',
  'opencode-go',
  'openrouter',
  'openai',
];

const String _thinkingOff = 'off';

/// Connect → fetch `/models` → pick model. Apply rebuilds the session.
class AgentSettingsPanel extends StatefulWidget {
  const AgentSettingsPanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.httpClient,
  });

  final AgentController controller;
  final VoidCallback onClose;
  final http.Client? httpClient;

  @override
  State<AgentSettingsPanel> createState() => _AgentSettingsPanelState();
}

class _AgentSettingsPanelState extends State<AgentSettingsPanel> {
  late String _provider;
  late final TextEditingController _apiKey;
  var _models = const <AgentModelInfo>[];
  String? _selectedModel;
  String _thinking = _thinkingOff;
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
    _apiKey = TextEditingController();
    _thinking = prefs?.thinkingLevel ?? _thinkingOff;
  }

  @override
  void dispose() {
    _apiKey.dispose();
    super.dispose();
  }

  AgentModelInfo? get _selectedInfo {
    for (final model in _models) {
      if (model.id == _selectedModel) {
        return model;
      }
    }
    return null;
  }

  bool get _modelEnabled => _models.isNotEmpty && !_busy && _provider != 'fake';

  Future<void> _connect() async {
    if (_busy || _provider == 'fake') {
      return;
    }
    final key = _apiKey.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste an API key to Connect');
      return;
    }
    final baseUrl = agentHttpPresets[_provider]?.defaultBaseUrl;
    if (baseUrl == null) {
      setState(() => _error = 'Unknown provider');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final models = await fetchAgentModels(
        baseUrl: baseUrl,
        apiKey: key,
        headers: agentProviderHeaders(
          presetId: _provider,
          sessionId: 'catalog',
        ),
        httpClient: widget.httpClient,
      );
      if (!mounted) {
        return;
      }
      if (models.isEmpty) {
        setState(() {
          _models = const [];
          _selectedModel = null;
          _thinking = _thinkingOff;
          _error = 'No models returned';
        });
        return;
      }
      final preferred = widget.controller.prefs?.model;
      final selected = models.any((model) => model.id == preferred)
          ? preferred!
          : models.first.id;
      final info = models.firstWhere((model) => model.id == selected);
      final preferredThinking = widget.controller.prefs?.thinkingLevel;
      final thinking =
          preferredThinking != null &&
              info.thinkingLevels.contains(preferredThinking)
          ? preferredThinking
          : _thinkingOff;
      setState(() {
        _models = models;
        _selectedModel = selected;
        _thinking = thinking;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _models = const [];
          _selectedModel = null;
          _thinking = _thinkingOff;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _apply({required bool fake}) async {
    if (_busy) {
      return;
    }
    if (!fake && (_selectedModel == null || _models.isEmpty)) {
      setState(() => _error = 'Connect and pick a model first');
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
          model: _selectedModel,
          apiKey: _apiKey.text,
          thinkingLevel: _thinking == _thinkingOff ? null : _thinking,
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

  void _onProvider(String? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _provider = value;
      _models = const [];
      _selectedModel = null;
      _thinking = _thinkingOff;
      _error = null;
    });
  }

  void _onModel(String? value) {
    if (value == null) {
      return;
    }
    AgentModelInfo? info;
    for (final model in _models) {
      if (model.id == value) {
        info = model;
        break;
      }
    }
    setState(() {
      _selectedModel = value;
      if (info == null || info.thinkingLevels.isEmpty) {
        _thinking = _thinkingOff;
      } else if (!info.thinkingLevels.contains(_thinking)) {
        _thinking = _thinkingOff;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final live = _provider != 'fake';
    final thinkingLevels = _selectedInfo?.thinkingLevels ?? const [];

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
                DropdownMenuItem(value: id, child: Text(_providerLabel(id))),
            ],
            onChanged: _busy ? null : _onProvider,
          ),
          if (live) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('agent-settings-api-key'),
                    controller: _apiKey,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'API key',
                      hintText: 'Not saved to disk',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('agent-settings-connect'),
                  onPressed: _busy ? null : _connect,
                  child: const Text('Connect'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            KeyedSubtree(
              key: ValueKey('catalog-${_models.length}-$_selectedModel'),
              child: DropdownButtonFormField<String>(
                key: const Key('agent-settings-model'),
                initialValue: _selectedModel,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Model',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Connect to load models'),
                items: [
                  for (final model in _models)
                    DropdownMenuItem(
                      value: model.id,
                      child: Text(
                        model.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _modelEnabled ? _onModel : null,
              ),
            ),
            if (thinkingLevels.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('agent-settings-thinking'),
                initialValue: thinkingLevels.contains(_thinking)
                    ? _thinking
                    : _thinkingOff,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Thinking',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: _thinkingOff,
                    child: Text('off'),
                  ),
                  for (final level in thinkingLevels)
                    DropdownMenuItem(value: level, child: Text(level)),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _thinking = value);
                      },
              ),
            ],
          ],
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
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                key: const Key('agent-settings-fake'),
                onPressed: _busy ? null : () => _apply(fake: true),
                child: const Text('Use Fake'),
              ),
              FilledButton(
                key: const Key('agent-settings-apply'),
                onPressed: _busy || !live || !_modelEnabled
                    ? null
                    : () => _apply(fake: false),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _providerLabel(String id) {
    return switch (id) {
      'fake' => 'Fake',
      'opencode-go' => 'OpenCode Go',
      'openrouter' => 'OpenRouter',
      'openai' => 'OpenAI',
      _ => id,
    };
  }
}
