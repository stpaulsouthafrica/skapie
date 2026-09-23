import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/cable_drag.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('compatible ports warm up as the cable nears; others stay still', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final text = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(500, 0),
    );
    final document = kitApi.store.document;
    final llmFrame = document.objectById(llm.first)!;
    String key(KitPortKind kind) => portReadinessKey(kind, llm.first);

    final far = cablePortReadiness(
      document: document,
      sourceFrameId: text.first,
      sourceKind: KitPortKind.textOut,
      cursor: Offset.zero,
      zoom: 1,
    );
    expect(far[key(KitPortKind.llmInput)], cablePortReadinessBase);
    expect(far[key(KitPortKind.llmContext)], cablePortReadinessBase);
    expect(far.containsKey(key(KitPortKind.llmTools)), isFalse);
    expect(far.containsKey(key(KitPortKind.llmOutput)), isFalse);
    expect(
      far.containsKey(portReadinessKey(KitPortKind.textIn, text.first)),
      isFalse,
    );

    final near = cablePortReadiness(
      document: document,
      sourceFrameId: text.first,
      sourceKind: KitPortKind.textOut,
      cursor: llmInputCenter(llmFrame) + const Offset(-40, 0),
      zoom: 1,
    );
    expect(near[key(KitPortKind.llmInput)]!, greaterThan(0.6));
    expect(
      near[key(KitPortKind.llmInput)]!,
      greaterThan(near[key(KitPortKind.llmContext)]!),
    );

    final on = cablePortReadiness(
      document: document,
      sourceFrameId: text.first,
      sourceKind: KitPortKind.textOut,
      cursor: llmInputCenter(llmFrame),
      zoom: 1,
    );
    expect(on[key(KitPortKind.llmInput)], 1);
  });
}
