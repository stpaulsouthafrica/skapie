import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('chat panel Echo with Fake model does not resize canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final session = AgentSession(model: FakeAgentModel(), kitApi: kitApi);
    await tester.pumpWidget(
      SkapieApp(store: store, kitApi: kitApi, agentSession: session),
    );

    final before = tester.getSize(find.byType(CanvasViewport));
    await tester.tap(find.byTooltip('Chat'));
    await tester.pump();
    expect(tester.getSize(find.byType(CanvasViewport)), before);

    await tester.enterText(find.byKey(const Key('agent-chat-input')), 'hello');
    await tester.tap(find.byKey(const Key('agent-chat-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('hello'), findsWidgets);
    expect(find.text('Echo: hello'), findsOneWidget);
    expect(store.document.objects, isEmpty);
    expect(tester.getSize(find.byType(CanvasViewport)), before);
  });
}
