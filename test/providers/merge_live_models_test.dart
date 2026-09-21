import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent_models_catalog.dart';
import 'package:skapie/providers/merge_live_models.dart';
import 'package:skapie/providers/model_surface.dart';
import 'package:skapie/providers/provider_model.dart';

void main() {
  const catalog = [
    ProviderModel(
      id: 'deepseek-v4-flash',
      surface: ModelSurface.completions,
      displayName: 'DeepSeek V4 Flash',
    ),
    ProviderModel(
      id: 'gpt-5.6-luna',
      surface: ModelSurface.responses,
      displayName: 'GPT 5.6 Luna',
    ),
    ProviderModel(id: 'hidden', surface: ModelSurface.completions, show: false),
    ProviderModel(id: 'offline-only', surface: ModelSurface.messages),
  ];

  test('live ∩ chart keeps surface; chart-only ids are omitted', () {
    final merged = mergeLiveModelsWithCatalog(
      live: const [
        AgentModelInfo(
          id: 'deepseek-v4-flash',
          displayName: 'deepseek-v4-flash',
        ),
        AgentModelInfo(id: 'gpt-5.6-luna', displayName: 'gpt-5.6-luna'),
      ],
      providerId: 'opencode-go',
      catalog: catalog,
    );
    expect(merged.map((m) => m.id).toList(), [
      'deepseek-v4-flash',
      'gpt-5.6-luna',
    ]);
    expect(merged.first.surface, ModelSurface.completions);
    expect(merged.first.displayName, 'DeepSeek V4 Flash');
    expect(merged.first.selectable, isTrue);
    expect(merged.last.surface, ModelSurface.responses);
  });

  test('unknown live ids are unverified and not selectable', () {
    final merged = mergeLiveModelsWithCatalog(
      live: const [
        AgentModelInfo(id: 'brand-new-go', displayName: 'brand-new-go'),
        AgentModelInfo(
          id: 'deepseek-v4-flash',
          displayName: 'deepseek-v4-flash',
        ),
      ],
      providerId: 'opencode-go',
      catalog: catalog,
    );
    expect(merged, hasLength(2));
    expect(merged.first.id, 'brand-new-go');
    expect(merged.first.selectable, isFalse);
    expect(merged.first.surface, isNull);
    expect(merged.first.subtitle, unverifiedCatalogSubtitle);
    expect(merged.last.selectable, isTrue);
    expect(
      firstSelectableModelId(merged, preferred: 'brand-new-go'),
      'deepseek-v4-flash',
    );
  });

  test('hidden catalog rows stay out of the picker even when live', () {
    final merged = mergeLiveModelsWithCatalog(
      live: const [AgentModelInfo(id: 'hidden', displayName: 'hidden')],
      providerId: 'opencode-go',
      catalog: catalog,
    );
    expect(merged, isEmpty);
  });

  test('non OpenCode Go providers keep the live list', () {
    const live = [
      AgentModelInfo(id: 'gpt-4o-mini', displayName: 'gpt-4o-mini'),
    ];
    expect(
      mergeLiveModelsWithCatalog(
        live: live,
        providerId: 'openai',
        catalog: catalog,
      ),
      live,
    );
  });
}
