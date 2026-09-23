import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/cable_layer.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
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

    final incoming = ports.firstWhere(
      (port) => port.kind == KitPortKind.textIn,
    );
    final output = ports.firstWhere((port) => port.kind == KitPortKind.textOut);
    final input = ports.firstWhere((port) => port.kind == KitPortKind.llmInput);
    expect(incoming.center, textInputCenter(textFrame));
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
      llmFrame.y + llmRegionLabelCenter(llmFrame.height, 4),
    );
    expect(llmFrame.height, llmFrameHeight);
    final toolPorts = ports.where((port) => port.frameId == toolFrame.id);
    expect(toolPorts.single.center, toolOutputCenter(toolFrame));
    expect(
      ports.firstWhere((port) => port.frameId == toolFrame.id).center.dx,
      toolFrame.x + toolFrame.width,
    );
    expect(input.peerId, llm.last);
    expect(kitCornerRadius(llmFrame), kitRadius);
    expect(kitCornerRadius(textFrame), kitRadius);

    final compact =
        llmRegionLabelCenter(llmFrameHeight, 1) -
        llmRegionLabelCenter(llmFrameHeight, 0);
    final spread = llmRegionLabelCenter(400, 1) - llmRegionLabelCenter(400, 0);
    expect(spread, greaterThan(compact));

    expect(hitKitPort(ports, output.center)?.kind, KitPortKind.textOut);
    expect(hitKitPort(ports, input.center + const Offset(40, 40)), isNull);
  });

  test('a text kit is only as tall as its two-line preview', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final ids = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    final frame = kitApi.store.document.objectById(ids.first)!;
    expect(frame.height, textFrameHeight);
    kitApi.updateFrame(id: frame.id, height: 150);
    fitPlacedTextKits(kitApi);
    expect(kitApi.store.document.objectById(frame.id)!.height, textFrameHeight);
  });

  test('output count ignores connections whose target was deleted', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final kept = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    final removed = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(0, 200),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: kept.first,
      port: llmTextOutPort,
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: removed.first,
      port: llmTextOutPort,
    );
    expect(
      llmConnectionCount(
        kitApi.store.document,
        llm.last,
        KitPortKind.llmOutput,
      ),
      2,
    );
    removeKitSelection(kitApi: kitApi, selectedId: removed.first);
    expect(
      llmConnectionCount(
        kitApi.store.document,
        llm.last,
        KitPortKind.llmOutput,
      ),
      1,
    );
  });

  test('a text kit summary keeps the first line and counts the rest', () {
    expect(textKitSummary('').firstLine, isEmpty);
    expect(textKitSummary('Hello').moreLabel, isEmpty);
    expect(textKitSummary('Hello\nnext').moreLabel, '+1 Line');
    expect(textKitSummary('Hello\n\n\n').moreLabel, '+3 Lines');
    expect(textKitSummary('Hello\r\nnext').firstLine, 'Hello');
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

  test('LLM output writes the reply into a cabled text kit', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(800, 0),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: text.first,
      port: llmTextOutPort,
    );
    expect(kitPortAccepts(KitPortKind.llmOutput, KitPortKind.textIn), isTrue);
    final frame = kitApi.store.document.objectById(text.first)!;
    final cable = sceneCables(kitApi.store.document)
        .singleWhere((item) => item.port == llmTextOutPort);
    expect(cable.to, textInputCenter(frame));

    writeLlmReplyToTextKits(
      kitApi: kitApi,
      llmBodyId: llm.last,
      text: 'Here are the files',
    );
    expect(textKitContent(kitApi.store.document, frame), 'Here are the files');
  });

  test('ports list connection counts and a drag can start on an input', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final text = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
    final first = kitApi.instantiate(
      worldToolKitId('list_kits'),
      origin: const Offset(0, 300),
    );
    final second = kitApi.instantiate(
      worldToolKitId('list_kits'),
      origin: const Offset(0, 420),
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: first.first,
      llmBodyId: llm.last,
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: second.first,
      llmBodyId: llm.last,
    );
    final document = kitApi.store.document;
    expect(llmConnectionCount(document, llm.last, KitPortKind.llmTools), 2);
    expect(llmPortAcceptsMany(KitPortKind.llmTools), isTrue);
    expect(llmConnectionCount(document, llm.last, KitPortKind.llmInput), 0);

    final ports = kitPorts(document);
    connectKitPorts(
      kitApi: kitApi,
      from: ports.firstWhere((port) => port.kind == KitPortKind.llmInput),
      to: ports.firstWhere((port) => port.kind == KitPortKind.textOut),
    );
    expect(
      llmConnectionCount(kitApi.store.document, llm.last, KitPortKind.llmInput),
      1,
    );
    expect(kitPortsConnect(KitPortKind.llmInput, KitPortKind.textOut), isTrue);
    expect(
      llmRunStatusOf(document.objectById(llm.last), running: false),
      LlmRunStatus.ready,
    );
    expect(
      llmRunStatusOf(document.objectById(llm.last), running: true),
      LlmRunStatus.running,
    );
  });

  test('a cable pulses only while its tool is being called', () {
    final tool = SceneCable(
      id: 'tool',
      ownerId: 'tool-frame',
      port: llmToolsPort,
      sourceId: 'tool-frame',
      targetFrameId: 'llm-frame',
      from: Offset.zero,
      to: const Offset(10, 0),
      color: const Color(0xFF000000),
      targetBodyId: 'llm-body',
      affectsRun: true,
    );
    expect(
      cableInvocationFlow(
        cable: tool,
        runningBodyId: 'llm-body',
        activeToolFrameId: null,
        clock: 0.2,
      ),
      isNull,
    );
    expect(
      cableInvocationFlow(
        cable: tool,
        runningBodyId: 'llm-body',
        activeToolFrameId: 'tool-frame',
        clock: 0.2,
      ),
      isNotNull,
    );
    final input = SceneCable(
      id: 'input',
      ownerId: 'text',
      port: llmInputPort,
      sourceId: 'text',
      targetFrameId: 'llm-frame',
      from: Offset.zero,
      to: const Offset(10, 0),
      color: const Color(0xFF000000),
      targetBodyId: 'llm-body',
      affectsRun: true,
    );
    expect(
      cableInvocationFlow(
        cable: input,
        runningBodyId: 'llm-body',
        activeToolFrameId: 'tool-frame',
        clock: 0.2,
      ),
      isNull,
    );
  });
}

List<KitPort> portsOf(SceneDocument document) => kitPorts(document);
