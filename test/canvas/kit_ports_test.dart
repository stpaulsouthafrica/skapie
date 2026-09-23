import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/cable_activity.dart';
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
      kitPortAccepts(KitPortKind.llmConversation, KitPortKind.conversationIn),
      isTrue,
    );
    expect(
      kitPortAccepts(KitPortKind.conversationOut, KitPortKind.llmConversation),
      isFalse,
    );
    expect(
      kitPortAccepts(KitPortKind.textOut, KitPortKind.llmConversation),
      isFalse,
    );
    expect(
      kitPortAccepts(KitPortKind.llmOutput, KitPortKind.conversationIn),
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

  test('LLM Conversation leaves on the right and lands on Conversation In', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final conversation = kitApi.instantiate(
      harnessConversationKitId,
      origin: Offset.zero,
    );
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final frame = kitApi.store.document.objectById(conversation.first)!;
    final llmFrame = kitApi.store.document.objectById(llm.first)!;
    final ports = kitPorts(kitApi.store.document);
    final incoming = ports.firstWhere(
      (port) =>
          port.frameId == frame.id && port.kind == KitPortKind.conversationIn,
    );
    final outgoing = ports.firstWhere(
      (port) =>
          port.frameId == frame.id && port.kind == KitPortKind.conversationOut,
    );
    final llmConversation = ports.firstWhere(
      (port) => port.kind == KitPortKind.llmConversation,
    );
    expect(incoming.center, textInputCenter(frame));
    expect(outgoing.center, textOutputCenter(frame));
    expect(llmConversation.center.dx, llmFrame.x + llmFrame.width);
    expect(kitPortIsOutput(KitPortKind.llmConversation), isTrue);
    expect(llmConversation.center.dy, lessThan(llmOutputCenter(llmFrame).dy));
    expect(llmToolsCenter(llmFrame).dx, llmFrame.x);

    connectKitPorts(
      kitApi: kitApi,
      from: ports.firstWhere((port) => port.kind == KitPortKind.llmOutput),
      to: incoming,
    );
    expect(sceneCables(kitApi.store.document), isEmpty);

    connectKitPorts(kitApi: kitApi, from: incoming, to: llmConversation);
    final cable = sceneCables(kitApi.store.document).single;
    expect(cable.port, llmConversationPort);
    expect(cable.from, llmConversationCenter(llmFrame));
    expect(cable.to, textInputCenter(frame));
    expect(llmConversationHistory(kitApi.store.document, llm.last), isEmpty);
    expect(
      kitHasLink(
        kitApi.store.document.objectById(frame.id)!,
        to: llm.last,
        port: llmConversationPort,
      ),
      isTrue,
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
    kitApi.instantiate(boardTextKitId, origin: Offset.zero);
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

  test('a Conversation cable flashes with the reply write, not the read', () {
    final conversation = SceneCable(
      id: 'conversation',
      ownerId: 'conversation-frame',
      port: llmConversationPort,
      sourceId: 'llm-frame',
      targetFrameId: 'conversation-frame',
      from: Offset.zero,
      to: const Offset(10, 0),
      color: const Color(0xFF000000),
      targetBodyId: 'llm-body',
      affectsRun: true,
    );
    expect(
      cableCarriesActivity(
        conversation,
        const CableActivity(runningBodyId: 'llm-body'),
      ),
      isFalse,
    );
    expect(
      cableCarriesActivity(
        conversation,
        const CableActivity(writingBodyId: 'llm-body'),
      ),
      isTrue,
    );
    expect(cableWritesReply(conversation, 'llm-body'), isTrue);
    expect(cableWritesReply(conversation, 'other-body'), isFalse);
  });

  test('a cable flashes only while that transfer is live', () {
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
    final seeding = CableActivity(
      runningBodyId: 'llm-body',
      seedPorts: {llmInputPort},
    );
    expect(cableCarriesActivity(tool, seeding), isFalse);
    final calling = CableActivity(
      runningBodyId: 'llm-body',
      seedPorts: {llmInputPort},
      activeToolFrameId: 'tool-frame',
    );
    expect(cableCarriesActivity(tool, calling), isTrue);
    expect(cableActivityTowardSource(tool, calling), isTrue);
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
    expect(cableCarriesActivity(input, calling), isTrue);
    expect(cableActivityTowardSource(input, calling), isFalse);
    final context = SceneCable(
      id: 'context',
      ownerId: 'prompt',
      port: llmContextPort,
      sourceId: 'prompt',
      targetFrameId: 'llm-frame',
      from: Offset.zero,
      to: const Offset(10, 0),
      color: const Color(0xFF000000),
      targetBodyId: 'llm-body',
      affectsRun: true,
    );
    expect(cableCarriesActivity(context, calling), isFalse);
    final repository = SceneCable(
      id: 'repo',
      ownerId: 'repo-frame',
      port: repositoryPort,
      sourceId: 'repo-frame',
      targetFrameId: 'tool-frame',
      from: Offset.zero,
      to: const Offset(10, 0),
      color: const Color(0xFF000000),
      targetBodyId: 'tool-frame',
      affectsRun: true,
    );
    expect(cableCarriesActivity(repository, seeding), isFalse);
    expect(cableCarriesActivity(repository, calling), isTrue);
    expect(cableActivityTowardSource(repository, calling), isTrue);
    final output = SceneCable(
      id: 'output',
      ownerId: 'llm-body',
      port: llmTextOutPort,
      sourceId: 'llm-frame',
      targetFrameId: 'reply',
      from: Offset.zero,
      to: const Offset(10, 0),
      color: const Color(0xFF000000),
      targetBodyId: 'reply',
      affectsRun: false,
    );
    expect(cableCarriesActivity(output, calling), isFalse);
    expect(
      cableCarriesActivity(
        output,
        const CableActivity(writingBodyId: 'llm-body'),
      ),
      isTrue,
    );
    expect(
      cableActivityTowardSource(
        output,
        const CableActivity(writingBodyId: 'llm-body'),
      ),
      isFalse,
    );
  });

  test('a transfer fades only after its current pass finishes', () {
    const born = 2.0;
    expect(
      activityFadeAt(
        born: born,
        now: born + 0.1,
        cycle: cableFlashTravelSeconds,
        finishCycle: false,
      ),
      born + cableFlashTravelSeconds,
    );
    expect(
      activityFadeAt(
        born: born,
        now: born + 1,
        cycle: cableFlashTravelSeconds,
        finishCycle: false,
      ),
      born + 1,
    );
    const toolCycle = cableFlashTravelSeconds * 2;
    expect(
      activityFadeAt(
        born: born,
        now: born + 0.1,
        cycle: toolCycle,
        finishCycle: true,
      ),
      born + toolCycle,
    );
    expect(
      activityFadeAt(
        born: born,
        now: born + toolCycle + 0.05,
        cycle: toolCycle,
        finishCycle: true,
      ),
      born + toolCycle * 2,
    );
    expect(cableGlowEnvelope(elapsed: 0, sinceFade: null), 0);
    expect(cableGlowEnvelope(elapsed: cableGlowInSeconds, sinceFade: null), 1);
    expect(cableGlowEnvelope(elapsed: 1, sinceFade: cableGlowFadeSeconds), 0);
    expect(toolFlashIndex(elapsed: 0, count: 2), 0);
    expect(
      toolFlashIndex(elapsed: cableFlashTravelSeconds + 0.01, count: 2),
      1,
    );
    expect(toolFlashTravel(elapsed: 0, count: 2), 0);
    expect(
      cableGlowEnvelope(elapsed: cableFlashTravelSeconds, sinceFade: 0),
      1,
    );
    expect(
      cableGlowEnvelope(
        elapsed: cableFlashTravelSeconds + cableGlowFadeSeconds,
        sinceFade: cableGlowFadeSeconds,
      ),
      0,
    );
  });

  test('a tool call lights the tools cable and the repository cable', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final tool = kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: Offset.zero,
    );
    final repository = kitApi.instantiate(
      codingRepositoryKitId,
      origin: const Offset(-400, 0),
    );
    attachToolKit(
      kitApi: kitApi,
      toolObjectId: tool.first,
      llmBodyId: llm.last,
    );
    connectRepositoryToTool(
      kitApi: kitApi,
      repositoryFrameId: repository.first,
      toolFrameId: tool.first,
    );
    final members = cablesForToolCall(
      cables: sceneCables(kitApi.store.document),
      toolFrameId: tool.first,
      llmBodyId: llm.last,
    );
    expect(members.map((cable) => cable.port), [llmToolsPort, repositoryPort]);
    expect(
      cablesForToolCall(
        cables: sceneCables(kitApi.store.document),
        toolFrameId: tool.first,
        llmBodyId: llm.last,
        returning: true,
      ).map((cable) => cable.port),
      [repositoryPort, llmToolsPort],
    );
    expect(
      toolFrameIdForName(kitApi.store.document, llm.last, 'repo_list_files'),
      tool.first,
    );
    final request = CableActivity(
      runningBodyId: llm.last,
      activeToolFrameId: tool.first,
    );
    final result = CableActivity(
      toolResultPulse: 1,
      toolResultFrameId: tool.first,
      toolResultBodyId: llm.last,
    );
    final toolsCable = members.first;
    final repoCable = members.last;
    expect(cableActivityTowardSource(toolsCable, request), isTrue);
    expect(cableCarriesActivity(toolsCable, request), isTrue);
    expect(cableActivityTowardSource(toolsCable, result), isFalse);
    expect(cableCarriesActivity(toolsCable, result), isTrue);
    expect(cableActivityTowardSource(repoCable, result), isFalse);
    expect(cableCarriesActivity(repoCable, result), isTrue);
    expect(toolFlashHead(travel: 0, towardSource: true), closeTo(1, 0.001));
    expect(toolFlashHead(travel: 1, towardSource: true), closeTo(0, 0.001));
    expect(toolFlashHead(travel: 0, towardSource: false), closeTo(0, 0.001));
    expect(toolFlashHead(travel: 1, towardSource: false), closeTo(1, 0.001));
  });

  test('a run needs Output or Conversation', () {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    expect(llmRunHasSink(kitApi.store.document, llm.last), isFalse);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(400, 0),
    );
    connectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: text.first,
      port: llmTextOutPort,
    );
    expect(llmRunHasSink(kitApi.store.document, llm.last), isTrue);
    disconnectLlmOutput(
      kitApi: kitApi,
      sourceBodyId: llm.last,
      targetBodyId: text.first,
      port: llmTextOutPort,
    );
    expect(llmRunHasSink(kitApi.store.document, llm.last), isFalse);
    final conversation = kitApi.instantiate(
      harnessConversationKitId,
      origin: const Offset(0, 400),
    );
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: conversation.first,
      llmBodyId: llm.last,
      port: llmConversationPort,
    );
    expect(llmRunHasSink(kitApi.store.document, llm.last), isTrue);
  });
}

List<KitPort> portsOf(SceneDocument document) => kitPorts(document);
