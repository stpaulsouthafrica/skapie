import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/world/kits.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    KitApi kitApi,
    SelectionController selection,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              height: 700,
              child: InspectorPanel(
                store: kitApi.store,
                selection: selection,
                kitApi: kitApi,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('a Text → LLM Input cable shows both ends and the text', (
    tester,
  ) async {
    final kitApi = createAppKitApi(store: SceneStore());
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final text = kitApi.instantiate(
      boardTextKitId,
      origin: const Offset(-400, 0),
    );
    kitApi.updateProps(text.last, {'content': 'summarise the repo'});
    connectTextToLlm(
      kitApi: kitApi,
      textObjectId: text.first,
      llmBodyId: llm.last,
    );
    final selection = SelectionController()
      ..selectCable(sceneCables(kitApi.store.document).single.id);
    await pump(tester, kitApi, selection);

    expect(find.byKey(const Key('connection-inspector')), findsOneWidget);
    expect(textOf(tester, 'connection-source'), 'Text · Out');
    expect(textOf(tester, 'connection-destination'), 'LLM · Input');
    expect(textOf(tester, 'connection-role'), 'Data · Text');
    expect(textOf(tester, 'connection-preview'), 'summarise the repo');
    expect(textOf(tester, 'connection-last-use'), 'No run yet this session');
    expect(find.text('Carries now'), findsOneWidget);

    await tester.tap(find.text('Cut cable'));
    await tester.pump();
    expect(sceneCables(kitApi.store.document), isEmpty);
    expect(selection.selectedCableId, isNull);
    kitApi.store.undo();
    expect(sceneCables(kitApi.store.document), hasLength(1));
  });

  testWidgets('a Repository → read tool cable reads as a grant', (
    tester,
  ) async {
    final kitApi = createAppKitApi(store: SceneStore());
    final tool = kitApi.instantiate(
      worldToolKitId('repo_list_files'),
      origin: Offset.zero,
    );
    final repository = kitApi.instantiate(
      codingRepositoryKitId,
      origin: const Offset(-400, 0),
    );
    kitApi.updateProps(repository.first, {repositoryPathProp: '/src/app'});
    connectRepositoryToTool(
      kitApi: kitApi,
      repositoryFrameId: repository.first,
      toolFrameId: tool.first,
    );
    final selection = SelectionController()
      ..selectCable(sceneCables(kitApi.store.document).single.id);
    await pump(tester, kitApi, selection);

    expect(textOf(tester, 'connection-source'), 'Repository · Out');
    expect(textOf(tester, 'connection-destination'), 'Tool · Repository');
    expect(textOf(tester, 'connection-role'), 'Grant · Repository');
    expect(textOf(tester, 'connection-preview'), 'Read access to /src/app');
    expect(find.text('Grants'), findsOneWidget);
    expect(find.text('Carries now'), findsNothing);
  });
}
