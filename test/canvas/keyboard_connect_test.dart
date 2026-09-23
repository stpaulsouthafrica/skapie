import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/keyboard_connect.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('Tab walks kit frames from the top, then the left', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final lower = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(40, 200),
    );
    final upperRight = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(300, 0),
    );
    final upperLeft = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-200, 0),
    );
    final document = kitApi.store.document;

    expect(
      cycleKitFrameId(document: document, selectedId: null, step: 1),
      upperLeft.first,
    );
    expect(
      cycleKitFrameId(document: document, selectedId: upperLeft.first, step: 1),
      upperRight.first,
    );
    expect(
      cycleKitFrameId(
        document: document,
        selectedId: upperRight.first,
        step: 1,
      ),
      lower.first,
    );
    expect(
      cycleKitFrameId(document: document, selectedId: lower.first, step: -1),
      upperRight.first,
    );
  });

  test('P walks the selected kit ports in draw order', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final ports = [
      for (final port in kitPorts(kitApi.store.document))
        if (port.frameId == llm.first) port,
    ];

    expect(
      cyclePortKind(ports: ports, current: null, step: 1),
      KitPortKind.llmInput,
    );
    expect(
      cyclePortKind(ports: ports, current: KitPortKind.llmInput, step: 1),
      KitPortKind.llmContext,
    );
    expect(
      cyclePortKind(ports: ports, current: KitPortKind.llmInput, step: -1),
      ports.last.kind,
    );
    expect(cyclePortKind(ports: const [], current: null, step: 1), isNull);
  });

  test('Connect lists compatible free targets and skips the cabled pair', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 200),
    );
    final other = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(400, 200),
    );
    kitApi.instantiate(harnessConversationKitId, origin: const Offset(0, 400));
    kitApi.updateProps(text.first, {'name': 'Note'});
    kitApi.updateProps(other.first, {'name': 'Note'});
    final document = kitApi.store.document;
    final input = kitPorts(document).firstWhere(
      (port) => port.frameId == llm.first && port.kind == KitPortKind.llmInput,
    );
    final textOut = kitPorts(document).firstWhere(
      (port) => port.frameId == text.first && port.kind == KitPortKind.textOut,
    );

    final open = connectChoices(document: document, source: input);
    expect(
      open.map((choice) => choice.port.frameId),
      containsAll([text.first, other.first]),
    );
    expect(open.map((choice) => choice.port.kind).toSet(), {
      KitPortKind.textOut,
    });
    expect(open.map((choice) => choice.label), [
      'Note · Out · ${text.first}',
      'Note · Out · ${other.first}',
    ]);

    connectKitPorts(kitApi: kitApi, from: textOut, to: input);
    final after = connectChoices(
      document: kitApi.store.document,
      source: input,
    );
    expect(after.map((choice) => choice.port.frameId), [other.first]);
    expect(after.single.label, 'Note · Out');

    final live = portConnections(
      document: kitApi.store.document,
      source: input,
    );
    expect(live.single.cable.sourceId, text.first);
    expect(live.single.label, 'Cut · Note · Out');
    final output = kitPorts(kitApi.store.document).firstWhere(
      (port) =>
          port.frameId == llm.first && port.kind == KitPortKind.llmOutput,
    );
    expect(
      portConnections(document: kitApi.store.document, source: output),
      isEmpty,
    );
  });
}
