import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  test('llmKitBodyForSelection maps frame or body to the compound body', () {
    final first = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final second = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final firstFrame = kitApi.store.document.objectById(first.first)!;
    final firstBody = kitApi.store.document.objectById(first.last)!;
    final secondBody = kitApi.store.document.objectById(second.last)!;

    expect(
      llmKitBodyForSelection(
        document: kitApi.store.document,
        selectedId: firstBody.id,
      )?.id,
      firstBody.id,
    );
    expect(
      llmKitBodyForSelection(
        document: kitApi.store.document,
        selectedId: firstFrame.id,
      )?.id,
      firstBody.id,
    );
    expect(
      llmKitBodyForSelection(
        document: kitApi.store.document,
        selectedId: secondBody.id,
      )?.id,
      secondBody.id,
    );
    expect(
      llmKitBodyForSelection(document: kitApi.store.document, selectedId: null),
      isNull,
    );
  });

  test('publishLlmKit updates the targeted body only', () {
    final first = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final second = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    publishLlmKit(
      kitApi: kitApi,
      bodyId: second.last,
      prompt: 'targeted',
      reply: 'ok',
    );
    expect(kitApi.store.document.objectById(first.last)!.props['prompt'], '');
    expect(
      kitApi.store.document.objectById(second.last)!.props['prompt'],
      'targeted',
    );
    expect(kitApi.store.document.objectById(second.last)!.props['reply'], 'ok');
  });
}
