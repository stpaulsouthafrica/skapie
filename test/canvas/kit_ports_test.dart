import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/conversation_turn.dart';
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
      ports.firstWhere((port) => port.kind == KitPortKind.llmOutput).center,
      llmOutputCenter(llmFrame),
    );
    expect(
      ports.firstWhere((port) => port.kind == KitPortKind.llmOutput).center.dy,
      llmFrame.y + llmFrame.height - textOutputInset,
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
    final frame = kitApi.store.document.objectById(text.first)!;
    expect(kitHasLink(frame, to: llm.last, port: llmInputPort), isTrue);
    expect(kitHasLink(frame, to: llm.last, port: llmContextPort), isTrue);
    expect(
      llmCableInput(kitApi.store.document, llm.last),
      'hello from the card',
    );

    disconnectText(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
      port: llmInputPort,
    );
    final after = kitApi.store.document.objectById(text.first)!;
    expect(kitHasLink(after, to: llm.last, port: llmInputPort), isFalse);
    expect(kitHasLink(after, to: llm.last, port: llmContextPort), isTrue);
    expect(llmCableInput(kitApi.store.document, llm.last), isEmpty);
  });

  test('context text and a cabled conversation become the next request', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final text = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    final conversation = kitApi.instantiate(
      harnessConversationKitId,
      origin: const Offset(0, 220),
    );
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    kitApi.updateProps(text.last, {'content': 'Texting from space'});
    appendConversationExchange(
      kitApi: kitApi,
      bodyId: conversation.last,
      userText: 'Text',
      assistantText: 'Hi',
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
      port: llmContextPort,
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: conversation.first,
      llmBodyId: llm.last,
      port: llmConversationPort,
    );

    final document = kitApi.store.document;
    expect(llmContextText(document, llm.last), 'Texting from space');
    expect(llmConversationHistory(document, llm.last), [
      const ConversationTurn(role: 'user', content: 'Text'),
      const ConversationTurn(role: 'assistant', content: 'Hi'),
    ]);
    expect(
      kitPortAccepts(KitPortKind.conversationOut, KitPortKind.llmConversation),
      isTrue,
    );
    expect(
      kitPortAccepts(KitPortKind.textOut, KitPortKind.llmConversation),
      isFalse,
    );
    expect(
      portsOf(document).any((port) => port.kind == KitPortKind.llmConversation),
      isTrue,
    );

    final cable = sceneCables(document)
        .singleWhere((item) => item.port == llmConversationPort);
    disconnectSceneCable(kitApi: kitApi, cable: cable);
    expect(llmConversationHistory(kitApi.store.document, llm.last), isEmpty);
    expect(
      llmContextText(kitApi.store.document, llm.last),
      'Texting from space',
    );
  });
}

List<KitPort> portsOf(SceneDocument document) => kitPorts(document);
