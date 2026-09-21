import 'dart:convert';

import 'package:skapie/providers/model_surface.dart';
import 'package:skapie/providers/provider_model.dart';

const String opencodeGoCatalogAsset =
    'lib/providers/opencode_go/opencode_go_catalog.json';

const String opencodeGoDefaultBaseUrl = 'https://opencode.ai/zen/go/v1';

/// Embedded copy of [opencodeGoCatalogAsset] so tests and runtime do not
/// depend on Flutter asset loading. Keep identical to the JSON file.
const String opencodeGoCatalogJson = r'''
{
  "provider": "opencode-go",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "models": [
    {"id": "glm-5.3-flash", "surface": "completions", "displayName": "GLM-5.3-Flash"},
    {"id": "glm-5.3", "surface": "completions", "displayName": "GLM-5.3"},
    {"id": "glm-5.2", "surface": "completions", "displayName": "GLM-5.2"},
    {"id": "glm-5.1", "surface": "completions", "displayName": "GLM-5.1"},
    {"id": "kimi-k3", "surface": "completions", "displayName": "Kimi K3"},
    {"id": "kimi-k2.7-code", "surface": "completions", "displayName": "Kimi K2.7 Code"},
    {"id": "kimi-k2.6", "surface": "completions", "displayName": "Kimi K2.6"},
    {"id": "longcat-2.0", "surface": "completions", "displayName": "LongCat-2.0"},
    {"id": "deepseek-v4.1-flash", "surface": "completions", "displayName": "DeepSeek V4.1 Flash"},
    {"id": "deepseek-v4-pro", "surface": "completions", "displayName": "DeepSeek V4 Pro"},
    {"id": "deepseek-v4-flash", "surface": "completions", "displayName": "DeepSeek V4 Flash"},
    {"id": "deepseek-v4-flash-vision-exp", "surface": "completions", "displayName": "DeepSeek V4 Flash Vision Exp"},
    {"id": "mimo-v2.5", "surface": "completions", "displayName": "MiMo-V2.5"},
    {"id": "mimo-v2.5-pro", "surface": "completions", "displayName": "MiMo-V2.5-Pro"},
    {"id": "hy4-preview", "surface": "completions", "displayName": "Hy4 preview"},
    {"id": "hy3", "surface": "completions", "displayName": "Hy3"},
    {"id": "qwen3.6-plus", "surface": "completions", "displayName": "Qwen3.6 Plus"},
    {"id": "qwen3.7-plus", "surface": "completions", "displayName": "Qwen3.7 Plus"},
    {"id": "qwen3.7-max", "surface": "completions", "displayName": "Qwen3.7 Max"},
    {"id": "qwen3.8-max", "surface": "completions", "displayName": "Qwen3.8 Max"},
    {"id": "minimax-m2.7", "surface": "completions", "displayName": "MiniMax M2.7"},
    {"id": "gpt-5.6-luna", "surface": "responses", "displayName": "GPT 5.6 Luna"},
    {"id": "grok-4.6", "surface": "responses", "displayName": "Grok 4.6"},
    {"id": "grok-4.7", "surface": "responses", "displayName": "Grok 4.7"},
    {"id": "muse-spark-1.2-contributor", "surface": "responses", "displayName": "Muse Spark 1.2 Contributor"},
    {"id": "muse-spark-1.3-contributor", "surface": "responses", "displayName": "Muse Spark 1.3 Contributor"},
    {"id": "minimax-m3", "surface": "messages", "displayName": "MiniMax M3"},
    {"id": "minimax-m2.5", "surface": "messages", "displayName": "MiniMax M2.5"},
    {"id": "qwen3.8-flash", "surface": "messages", "displayName": "Qwen3.8 Flash"}
  ]
}
''';

final List<ProviderModel> opencodeGoCatalog = parseOpenCodeGoCatalog(
  jsonDecode(opencodeGoCatalogJson),
);

final Map<String, ProviderModel> opencodeGoCatalogById = {
  for (final model in opencodeGoCatalog) model.id: model,
};

ProviderModel? lookupOpenCodeGoModel(String id) {
  final key = id.trim();
  if (key.isEmpty) {
    return null;
  }
  return opencodeGoCatalogById[key];
}

List<ProviderModel> parseOpenCodeGoCatalog(Object? decoded) {
  if (decoded is! Map) {
    throw const FormatException('OpenCode Go catalog must be an object');
  }
  final models = decoded['models'];
  if (models is! List) {
    throw const FormatException('OpenCode Go catalog models must be an array');
  }
  final parsed = <ProviderModel>[];
  final seen = <String>{};
  for (final item in models) {
    if (item is! Map) {
      continue;
    }
    final id = item['id']?.toString().trim() ?? '';
    if (id.isEmpty || seen.contains(id)) {
      continue;
    }
    final surface = ModelSurface.tryParse(item['surface']?.toString());
    if (surface == null) {
      throw FormatException('Unknown surface for $id');
    }
    seen.add(id);
    final name = item['displayName']?.toString().trim();
    parsed.add(
      ProviderModel(
        id: id,
        surface: surface,
        displayName: (name == null || name.isEmpty) ? null : name,
        show: item['show'] == false ? false : true,
        vanillaOk: item['vanillaOk'] == false ? false : true,
      ),
    );
  }
  return parsed;
}
