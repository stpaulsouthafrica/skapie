import 'package:http/http.dart' as http;
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/vanilla_completion.dart';
import 'package:skapie/kit_api/kit_api.dart';

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
    this.thinkingLevel,
    this.warning,
    this.sendKitTools = true,
  });

  final String presetId;
  final bool useFake;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final String? thinkingLevel;
  final String? warning;
  final bool sendKitTools;
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

class AgentRuntimeSources {
  const AgentRuntimeSources({
    this.dartDefineProvider = '',
    this.envProvider = '',
    this.dartDefineBaseUrl = '',
    this.envBaseUrl = '',
    this.dartDefineApiKey = '',
    this.envApiKey = '',
    this.dartDefineModel = '',
    this.envModel = '',
    this.environment = const {},
  });

  final String dartDefineProvider;
  final String envProvider;
  final String dartDefineBaseUrl;
  final String envBaseUrl;
  final String dartDefineApiKey;
  final String envApiKey;
  final String dartDefineModel;
  final String envModel;
  final Map<String, String> environment;
}

/// Last Apply prefs win over dart-define / env. Missing key/model still Fake.
ResolvedAgentRuntime mergeAgentRuntime({
  AgentPrefs? prefs,
  String? memoryApiKey,
  AgentRuntimeSources sources = const AgentRuntimeSources(),
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
  final merged = AgentRuntimeSources(
    dartDefineProvider: dartDefineProvider.isNotEmpty
        ? dartDefineProvider
        : sources.dartDefineProvider,
    envProvider: envProvider.isNotEmpty ? envProvider : sources.envProvider,
    dartDefineBaseUrl: dartDefineBaseUrl.isNotEmpty
        ? dartDefineBaseUrl
        : sources.dartDefineBaseUrl,
    envBaseUrl: envBaseUrl.isNotEmpty ? envBaseUrl : sources.envBaseUrl,
    dartDefineApiKey: dartDefineApiKey.isNotEmpty
        ? dartDefineApiKey
        : sources.dartDefineApiKey,
    envApiKey: envApiKey.isNotEmpty ? envApiKey : sources.envApiKey,
    dartDefineModel: dartDefineModel.isNotEmpty
        ? dartDefineModel
        : sources.dartDefineModel,
    envModel: envModel.isNotEmpty ? envModel : sources.envModel,
    environment: environment.isNotEmpty ? environment : sources.environment,
  );
  if (prefs != null) {
    final provider = prefs.providerId.trim();
    if (provider.isEmpty || provider == 'fake') {
      return ResolvedAgentRuntime(
        presetId: 'fake',
        useFake: true,
        sendKitTools: prefs.sendKitTools,
      );
    }
    final preset = agentHttpPresets[provider];
    final baseOverride = preset?.defaultBaseUrl == null
        ? (prefs.baseUrl ?? '')
        : '';
    final resolved = resolveAgentRuntime(
      dartDefineProvider: provider,
      dartDefineBaseUrl: baseOverride,
      dartDefineApiKey:
          _firstNonEmpty([
            memoryApiKey,
            prefs.apiKey,
            merged.dartDefineApiKey,
          ]) ??
          '',
      dartDefineModel: prefs.model ?? '',
      envApiKey: merged.envApiKey,
      environment: merged.environment,
    );
    return ResolvedAgentRuntime(
      presetId: resolved.presetId,
      useFake: resolved.useFake,
      baseUrl: resolved.baseUrl,
      apiKey: resolved.apiKey,
      model: resolved.model,
      thinkingLevel: prefs.thinkingLevel,
      warning: resolved.warning,
      sendKitTools: prefs.sendKitTools,
    );
  }
  return resolveAgentRuntime(
    dartDefineProvider: merged.dartDefineProvider,
    envProvider: merged.envProvider,
    dartDefineBaseUrl: merged.dartDefineBaseUrl,
    envBaseUrl: merged.envBaseUrl,
    dartDefineApiKey:
        _firstNonEmpty([memoryApiKey, merged.dartDefineApiKey]) ?? '',
    envApiKey: merged.envApiKey,
    dartDefineModel: merged.dartDefineModel,
    envModel: merged.envModel,
    environment: merged.environment,
  );
}

String agentStatusChip(ResolvedAgentRuntime runtime) {
  if (runtime.useFake) {
    return 'Fake';
  }
  final model = runtime.model?.trim() ?? '';
  if (model.isEmpty) {
    return runtime.presetId;
  }
  return '${runtime.presetId} · $model';
}

AgentSession buildAgentSession({
  required KitApi kitApi,
  required ResolvedAgentRuntime runtime,
}) {
  if (runtime.useFake) {
    return AgentSession(
      model: const FakeAgentModel(),
      kitApi: kitApi,
      includeTools: runtime.sendKitTools,
    );
  }
  final sessionId = 'agent_${DateTime.now().microsecondsSinceEpoch}';
  return AgentSession(
    model: OpenAiCompatibleAgentModel(
      baseUrl: runtime.baseUrl!,
      apiKey: runtime.apiKey!,
      model: runtime.model!,
      presetId: runtime.presetId,
      headers: agentProviderHeaders(
        presetId: runtime.presetId,
        sessionId: sessionId,
      ),
      reasoningEffort: runtime.presetId == 'openrouter'
          ? runtime.thinkingLevel
          : null,
    ),
    kitApi: kitApi,
    id: sessionId,
    includeTools: runtime.sendKitTools,
  );
}

VanillaCompletionClient? buildVanillaCompletion({
  required ResolvedAgentRuntime runtime,
  String? sessionId,
  http.Client? httpClient,
}) {
  if (runtime.useFake) {
    return null;
  }
  return VanillaCompletionClient(
    baseUrl: runtime.baseUrl!,
    apiKey: runtime.apiKey!,
    model: runtime.model!,
    presetId: runtime.presetId,
    headers: agentProviderHeaders(
      presetId: runtime.presetId,
      sessionId: sessionId ?? 'vanilla',
    ),
    httpClient: httpClient,
  );
}
