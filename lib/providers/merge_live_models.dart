import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';
import 'package:skapie/providers/provider_model.dart';

const String unverifiedCatalogSubtitle = 'not in Skapie catalog yet';

/// Live `/models` ∩ curated chart. Chart-only ids are omitted.
/// Unknown live ids stay visible but not selectable and are not completions.
List<AgentModelInfo> mergeLiveModelsWithCatalog({
  required List<AgentModelInfo> live,
  required String providerId,
  List<ProviderModel> catalog = const [],
}) {
  if (providerId != 'opencode-go') {
    return live;
  }
  final chart = catalog.isEmpty ? opencodeGoCatalog : catalog;
  final byId = {for (final model in chart) model.id: model};
  final merged = <AgentModelInfo>[];
  for (final liveModel in live) {
    final entry = byId[liveModel.id];
    if (entry == null) {
      merged.add(
        AgentModelInfo(
          id: liveModel.id,
          displayName: liveModel.displayName,
          thinkingLevels: liveModel.thinkingLevels,
          selectable: false,
          subtitle: unverifiedCatalogSubtitle,
        ),
      );
      continue;
    }
    if (!entry.show) {
      continue;
    }
    merged.add(
      AgentModelInfo(
        id: liveModel.id,
        displayName: entry.displayName ?? liveModel.displayName,
        thinkingLevels: liveModel.thinkingLevels,
        surface: entry.surface,
        selectable: entry.vanillaOk,
      ),
    );
  }
  return merged;
}

String? firstSelectableModelId(
  List<AgentModelInfo> models, {
  String? preferred,
}) {
  final want = preferred?.trim() ?? '';
  if (want.isNotEmpty) {
    for (final model in models) {
      if (model.id == want && model.selectable) {
        return model.id;
      }
    }
  }
  for (final model in models) {
    if (model.selectable) {
      return model.id;
    }
  }
  return null;
}
