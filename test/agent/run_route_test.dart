import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/run_ledger.dart';
import 'package:skapie/agent/run_route.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/world/kits.dart';

void main() {
  test(
    'a model event lights the input cable and leaves the tool cable still',
    () {
      final kitApi = createAppKitApi(store: SceneStore());
      final text = kitApi.instantiate(boardTextKitId, origin: Offset.zero);
      final llm = kitApi.instantiate(
        harnessLlmKitId,
        origin: const Offset(400, 0),
      );
      final tool = kitApi.instantiate(
        worldToolKitId('list_kits'),
        origin: const Offset(0, 240),
      );
      kitApi.updateProps(text.last, {'content': 'hello'});
      connectTextToLlm(
        kitApi: kitApi,
        textObjectId: text.first,
        llmBodyId: llm.last,
      );
      attachToolKit(
        kitApi: kitApi,
        toolObjectId: tool.first,
        llmBodyId: llm.last,
      );
      final document = kitApi.store.document;
      final route = routeIntoModel(
        document: document,
        bodyId: llm.last,
        ports: {llmInputPort},
        conversation: false,
      );
      final cables = sceneCables(document);
      final input = cables.where((cable) => cable.port == llmInputPort).single;
      final tools = cables.where((cable) => cable.port == llmToolsPort).single;
      expect(route.cables, [input.id]);
      expect(route.cables, isNot(contains(tools.id)));
      expect(route.kits, isNotEmpty);

      final toolRoute = routeForTool(
        document: document,
        bodyId: llm.last,
        toolFrameId: tool.first,
      );
      expect(toolRoute.cables, contains(tools.id));
      expect(toolRoute.cables, isNot(contains(input.id)));
      expect(toolRoute.kits, contains(tool.first));
    },
  );

  test('a recorded request keeps the body and drops the key', () {
    final text = redactedHttpRequest(
      url: 'https://opencode.ai/zen/go/v1/responses',
      headers: {
        'Authorization': 'Bearer sk-secret',
        'Content-Type': 'application/json',
      },
      body: {'model': 'muse-spark-1.3', 'input': 'hello'},
    );
    expect(text, contains('https://opencode.ai/zen/go/v1/responses'));
    expect(text, contains('muse-spark-1.3'));
    expect(text, contains('[redacted]'));
    expect(text, isNot(contains('sk-secret')));
  });

  test('an expanded event shows bounded detail and hides route ids', () {
    final event = RunEvent(
      schemaVersion: 1,
      sequence: 2,
      at: DateTime.utc(2026, 9, 24),
      kind: RunEventKind.toolCallStarted,
      payload: {
        'name': 'list_kits',
        'arguments': 'x' * 400,
        'kits': ['frame'],
        'cables': ['cable'],
      },
    );
    expect(runEventSummary(event), '2. Tool call started · list_kits');
    expect(runEventInspectAside(event), contains('At:'));
    expect(runEventInspectAside(event), isNot(contains('arguments:')));
    expect(runEventInspectBody(event), startsWith('x'));
    final lines = runEventDetailLines(event);
    expect(lines.join('\n'), contains('list_kits'));
    expect(lines.join('\n'), isNot(contains('frame')));
    expect(
      lines.firstWhere((line) => line.startsWith('arguments')).length,
      lessThan(400),
    );
  });
}
