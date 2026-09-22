import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_links.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  test('attach and detach write attachedTo via KitApi', () {
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final tool = kitApi.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 0),
    );
    final grant = kitApi.store.document.objects.firstWhere(
      (object) =>
          object.props[skapieKitProp] == 'tools.list_kits' &&
          object.props['toolName'] == 'list_kits',
    );

    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );
    expect(
      kitHasLink(
        kitApi.store.document.objectById(grant.id)!,
        to: llm.last,
        port: llmToolsPort,
      ),
      isTrue,
    );
    expect(attachedToolNames(kitApi: kitApi, llmBodyId: llm.last), [
      'list_kits',
    ]);

    detachToolKit(kitApi: kitApi, toolObjectId: grant.id);
    expect(kitLinksOf(kitApi.store.document.objectById(grant.id)!), isEmpty);
    expect(attachedToolNames(kitApi: kitApi, llmBodyId: llm.last), isEmpty);
  });

  test('unknown toolName is an error on the kit and is omitted', () {
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final tool = kitApi.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 0),
    );
    final grant = kitApi.store.document.objects.firstWhere(
      (object) => object.props['toolName'] == 'list_kits',
    );
    kitApi.updateProps(grant.id, {'toolName': 'nope.tool'});
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );

    final resolved = worldToolsForLlm(kitApi: kitApi, llmBodyId: llm.last);
    expect(resolved, isEmpty);
    expect(
      kitApi.store.document.objectById(grant.id)!.props['error'],
      contains('Unknown tool'),
    );
  });
}
