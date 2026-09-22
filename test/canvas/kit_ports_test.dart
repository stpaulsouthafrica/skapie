import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/world/kits.dart';

void main() {
  test('ports sit on the section they belong to', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final text = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final tool = kitApi.instantiate(
      worldToolKitId('list_kits'),
      origin: const Offset(0, 300),
    );
    final textFrame = kitApi.store.document.objectById(text.first)!;
    final llmFrame = kitApi.store.document.objectById(llm.first)!;
    final toolFrame = kitApi.store.document.objectById(tool.first)!;
    final ports = kitPorts(kitApi.store.document);

    final output = ports.firstWhere((port) => port.kind == KitPortKind.textOut);
    final input = ports.firstWhere((port) => port.kind == KitPortKind.llmInput);
    expect(output.center.dx, textFrame.x + textFrame.width);
    expect(output.center.dy, textFrame.y + textFrame.height - textOutputInset);
    expect(input.center.dx, llmFrame.x);
    expect(
      input.center.dy,
      llmFrame.y + llmRegionLabelCenter(llmFrame.height, 0),
    );
    expect(
      ports.firstWhere((port) => port.kind == KitPortKind.llmContext).center.dy,
      llmFrame.y + llmRegionLabelCenter(llmFrame.height, 1),
    );
    expect(
      ports.firstWhere((port) => port.kind == KitPortKind.llmTools).center.dx,
      llmFrame.x,
    );
    expect(
      ports.firstWhere((port) => port.kind == KitPortKind.llmOutput).center.dx,
      llmFrame.x + llmFrame.width,
    );
    expect(
      ports.firstWhere((port) => port.frameId == toolFrame.id).center.dx,
      toolFrame.x + toolFrame.width,
    );
    expect(input.peerId, llm.last);
    expect(kitCornerRadius(llmFrame), kitRadius);
    expect(kitCornerRadius(textFrame), kitRadius);

    expect(hitKitPort(ports, output.center)?.kind, KitPortKind.textOut);
    expect(hitKitPort(ports, input.center + const Offset(40, 40)), isNull);
  });

  test('text cabled into Input becomes the LLM prompt', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final text = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final bodyId = text.last;
    kitApi.updateProps(bodyId, {'content': 'hello from the card'});
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    expect(
      llmCableInput(kitApi.store.document, llm.last),
      'hello from the card',
    );

    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
      port: llmContextPort,
    );
    expect(llmCableInput(kitApi.store.document, llm.last), isEmpty);
    final frame = kitApi.store.document.objectById(text.first)!;
    expect(textConnectedPort(frame), llmContextPort);

    disconnectText(kitApi: kitApi, textObjectId: text.first);
    expect(
      textConnectedLlmId(kitApi.store.document.objectById(text.first)!),
      isEmpty,
    );
  });
}
