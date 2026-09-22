import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/llm_request_highlight.dart';
import 'package:skapie/app/llm_request_information.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('request highlighting colors the method, keys, and strings apart', () {
    const source = '''
POST https://example.test/v1/chat/completions

Authorization: <redacted>

{
  "model": "demo",
  "n": 1
}
''';
    final tokens = PaintTokens.dark();
    final root = highlightLlmRequest(source, tokens);
    final colors = <String, Color?>{};
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text != null && span.text!.trim().isNotEmpty) {
          colors[span.text!] = span.style?.color;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child);
        }
      }
    }

    walk(root);
    expect(colors['POST'], tokens.accent);
    expect(colors['"model"'], tokens.accent);
    expect(colors['"demo"'], isNot(tokens.accent));
    expect(colors['"demo"'], isNot(colors['1']));
    expect(colors['Authorization: '], tokens.muted);
  });

  testWidgets('request information collapses and opens full screen', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    kitApi.updateProps(ids.last, {'prompt': 'hello from the card'});
    final body = store.document.objectById(ids.last)!;
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: const FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaintScope(
            tokens: PaintTokens.dark(),
            child: LlmRequestInformation(
              body: body,
              kitApi: kitApi,
              controller: controller,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('llm-request-information')), findsNothing);
    expect(find.text('Request Information'), findsOneWidget);

    await tester.tap(find.byKey(const Key('llm-request-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('llm-request-information')), findsOneWidget);
    expect(find.textContaining('hello from the card'), findsOneWidget);

    await tester.tap(find.byKey(const Key('llm-request-expand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('llm-request-fullscreen')), findsOneWidget);
    expect(find.textContaining('hello from the card'), findsWidgets);

    await tester.tap(find.byKey(const Key('llm-request-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('llm-request-fullscreen')), findsNothing);
  });
}
