class AgentHttpPreset {
  const AgentHttpPreset({
    required this.id,
    this.defaultBaseUrl,
    required this.nativeKeyEnv,
  });

  final String id;
  final String? defaultBaseUrl;
  final String nativeKeyEnv;
}

const Map<String, AgentHttpPreset> agentHttpPresets = {
  'opencode-go': AgentHttpPreset(
    id: 'opencode-go',
    defaultBaseUrl: 'https://opencode.ai/zen/go/v1',
    nativeKeyEnv: 'OPENCODE_API_KEY',
  ),
  'openrouter': AgentHttpPreset(
    id: 'openrouter',
    defaultBaseUrl: 'https://openrouter.ai/api/v1',
    nativeKeyEnv: 'OPENROUTER_API_KEY',
  ),
  'openai': AgentHttpPreset(
    id: 'openai',
    defaultBaseUrl: 'https://api.openai.com/v1',
    nativeKeyEnv: 'OPENAI_API_KEY',
  ),
  'custom': AgentHttpPreset(id: 'custom', nativeKeyEnv: 'SKAPIE_AGENT_API_KEY'),
};

class ResolvedAgentRuntime {
  const ResolvedAgentRuntime({
    required this.presetId,
    required this.useFake,
    this.baseUrl,
    this.apiKey,
    this.model,
    this.warning,
  });

  final String presetId;
  final bool useFake;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final String? warning;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final resolved = _nonEmpty(value);
    if (resolved != null) {
      return resolved;
    }
  }
  return null;
}

/// Resolve provider preset, base URL, key, and model. Missing key or model → Fake.
ResolvedAgentRuntime resolveAgentRuntime({
  String dartDefineProvider = '',
  String envProvider = '',
  String dartDefineBaseUrl = '',
  String envBaseUrl = '',
  String dartDefineApiKey = '',
  String envApiKey = '',
  String dartDefineModel = '',
  String envModel = '',
  Map<String, String> environment = const {},
}) {
  final explicitBase = _firstNonEmpty([dartDefineBaseUrl, envBaseUrl]);
  final skapieKey = _firstNonEmpty([
    dartDefineApiKey,
    envApiKey,
    environment['SKAPIE_AGENT_API_KEY'],
  ]);
  var provider = _firstNonEmpty([dartDefineProvider, envProvider]);
  if (provider == null) {
    if (_nonEmpty(environment['OPENCODE_API_KEY']) != null) {
      provider = 'opencode-go';
    } else if (_nonEmpty(environment['OPENROUTER_API_KEY']) != null) {
      provider = 'openrouter';
    } else if (_nonEmpty(environment['OPENAI_API_KEY']) != null ||
        skapieKey != null) {
      provider = explicitBase != null ? 'custom' : 'openai';
    }
  }
  if (provider == null || provider == 'fake') {
    return const ResolvedAgentRuntime(presetId: 'fake', useFake: true);
  }
  final preset = agentHttpPresets[provider];
  if (preset == null) {
    return ResolvedAgentRuntime(
      presetId: 'fake',
      useFake: true,
      warning: 'Unknown SKAPIE_AGENT_PROVIDER "$provider"; using Fake.',
    );
  }
  final baseUrl = _firstNonEmpty([explicitBase, preset.defaultBaseUrl]);
  if (baseUrl == null) {
    return const ResolvedAgentRuntime(
      presetId: 'fake',
      useFake: true,
      warning: 'custom provider requires SKAPIE_AGENT_BASE_URL; using Fake.',
    );
  }
  final apiKey = _firstNonEmpty([skapieKey, environment[preset.nativeKeyEnv]]);
  if (apiKey == null) {
    return ResolvedAgentRuntime(
      presetId: 'fake',
      useFake: true,
      warning: 'No API key for $provider; using Fake.',
    );
  }
  final model = _firstNonEmpty([
    dartDefineModel,
    envModel,
    environment['SKAPIE_AGENT_MODEL'],
  ]);
  if (model == null) {
    return ResolvedAgentRuntime(
      presetId: 'fake',
      useFake: true,
      warning: 'SKAPIE_AGENT_MODEL is required for $provider; using Fake.',
    );
  }
  return ResolvedAgentRuntime(
    presetId: provider,
    useFake: false,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
  );
}

Map<String, String> agentProviderHeaders({
  required String presetId,
  required String sessionId,
}) {
  return switch (presetId) {
    'opencode-go' => {
      'x-opencode-session': sessionId,
      'User-Agent': 'skapie/0.1',
    },
    'openrouter' => {
      'HTTP-Referer': 'https://skapie.local',
      'X-Title': 'Skapie',
    },
    _ => const {},
  };
}
