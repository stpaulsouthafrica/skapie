import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/paint_tokens.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  test('new LLM and tool kit frames omit toy-blue fill', () {
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    kitApi.instantiate('tools.list_kits', origin: const Offset(400, 0));
    final frames = kitApi.store.document.objects.where(
      (object) => object.props[skapieRoleProp] == 'frame',
    );
    expect(frames, isNotEmpty);
    for (final frame in frames) {
      expect(frame.props['fill'], isNot('#7AA3C7'));
      expect(kitHasCustomFill(frame), isFalse);
    }
    final primitive = kitApi.addObject(typeId: 'box', x: 0, y: 0);
    expect(
      kitApi.store.document.objectById(primitive)!.props['fill'],
      '#7AA3C7',
    );
  });

  test('kitMembers groups LLM and tools.list_kits by the containing frame', () {
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final tool = kitApi.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 0),
    );
    final llmBody = kitApi.store.document.objectById(llm.last)!;
    final llmFrame = kitApi.store.document.objectById(llm.first)!;
    final grant = kitApi.store.document.objectById(tool.last)!;
    final toolFrame = kitApi.store.document.objectById(tool.first)!;

    expect(
      kitMembers(
        document: kitApi.store.document,
        selectedId: llmBody.id,
      )?.map((object) => object.id),
      unorderedEquals([llmFrame.id, llmBody.id]),
    );
    expect(
      kitMembers(
        document: kitApi.store.document,
        selectedId: grant.id,
      )?.map((object) => object.id),
      unorderedEquals([toolFrame.id, grant.id]),
    );
  });

  test('first LLM is named LLM and the next is LLM (2)', () {
    kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    kitApi.instantiate(harnessLlmKitId, origin: const Offset(400, 0));
    final frames = kitApi.store.document.objects
        .where(
          (object) =>
              object.props[skapieRoleProp] == 'frame' &&
              kitIdOf(object) == harnessLlmKitId,
        )
        .toList();
    expect(frames[0].props[kitNameProp], 'LLM');
    expect(frames[1].props[kitNameProp], 'LLM (2)');
    expect(
      colorToHex(kitAccentColor(frames[0])),
      colorToHex(PaintTokens.champagne),
    );
  });

  test('a renamed LLM keeps that name and accent', () {
    final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    for (final id in ids) {
      kitApi.updateProps(id, {kitNameProp: 'Blue', kitAccentProp: '#88CCFF'});
    }
    final frame = kitApi.store.document.objectById(ids.first)!;
    expect(kitDisplayName(kitApi.store.document, frame), 'Blue');
    expect(colorToHex(kitAccentColor(frame)), '#88CCFF');
    final next = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    expect(
      kitApi.store.document.objectById(next.first)!.props[kitNameProp],
      'LLM',
    );
  });

  test('removeKitSelection deletes the whole LLM compound', () {
    final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    removeKitSelection(kitApi: kitApi, selectedId: ids.last);
    expect(
      kitApi.store.document.objects.where(
        (object) => object.props[skapieKitProp] == harnessLlmKitId,
      ),
      isEmpty,
    );
  });

  test('removeKitSelection deletes a tool grant and refreshes LLM tools', () {
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final tool = kitApi.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 0),
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );
    expect(
      kitApi.store.document.objectById(llm.last)!.props['content'],
      contains('Tools: list_kits'),
    );

    removeKitSelection(kitApi: kitApi, selectedId: tool.last);
    expect(
      kitApi.store.document.objects.where(
        (object) => object.props[skapieKitProp] == 'tools.list_kits',
      ),
      isEmpty,
    );
    expect(
      kitApi.store.document.objectById(llm.last)!.props['content'],
      contains('Tools: none'),
    );
  });

  test('panel token stays the inspector gray', () {
    expect(colorToHex(PaintTokens.dark().panel), '#161618');
  });
}
