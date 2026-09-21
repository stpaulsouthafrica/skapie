import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/agent_settings_panel.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('Model is disabled until Connect succeeds', (tester) async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/models'));
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'kimi-k2.6'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final kitApi = createAppKitApi(store: SceneStore());
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      prefs: const AgentPrefs(providerId: 'opencode-go'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 600,
            child: AgentSettingsPanel(
              controller: controller,
              onClose: () {},
              httpClient: client,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('agent-settings-base-url')), findsNothing);
    expect(find.byKey(const Key('agent-settings-model')), findsOneWidget);
    final before = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('agent-settings-model')),
    );
    expect(before.onChanged, isNull);

    await tester.enterText(
      find.byKey(const Key('agent-settings-api-key')),
      'oc-test',
    );
    await tester.tap(find.byKey(const Key('agent-settings-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final after = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('agent-settings-model')),
    );
    expect(after.onChanged, isNotNull);
    expect(find.text('kimi-k2.6'), findsOneWidget);
  });

  testWidgets('Connect 401 shows error and leaves Model disabled', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return http.Response('nope', 401);
    });
    final kitApi = createAppKitApi(store: SceneStore());
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      prefs: const AgentPrefs(providerId: 'opencode-go'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 600,
            child: AgentSettingsPanel(
              controller: controller,
              onClose: () {},
              httpClient: client,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('agent-settings-api-key')),
      'bad',
    );
    await tester.tap(find.byKey(const Key('agent-settings-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('401'), findsOneWidget);
    final model = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('agent-settings-model')),
    );
    expect(model.onChanged, isNull);
    expect(controller.runtime.useFake, isTrue);
  });

  testWidgets('reopening settings keeps last model and remembered key', (
    tester,
  ) async {
    final kitApi = createAppKitApi(store: SceneStore());
    final controller = AgentController(
      kitApi: kitApi,
      session: AgentSession(model: FakeAgentModel(), kitApi: kitApi),
      runtime: const ResolvedAgentRuntime(
        presetId: 'opencode-go',
        useFake: false,
        model: 'kimi-k2.6',
        apiKey: 'oc-remember',
      ),
      prefs: const AgentPrefs(
        providerId: 'opencode-go',
        model: 'kimi-k2.6',
        apiKey: 'oc-remember',
      ),
      memoryApiKey: 'oc-remember',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 600,
            child: AgentSettingsPanel(controller: controller, onClose: () {}),
          ),
        ),
      ),
    );

    expect(find.text('kimi-k2.6'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('agent-settings-api-key')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'oc-remember',
    );
    expect(find.byKey(const Key('agent-settings-apply')), findsOneWidget);
  });
}
