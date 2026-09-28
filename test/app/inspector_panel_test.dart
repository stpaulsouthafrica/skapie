import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

void main() {
  testWidgets('Inspector folder buttons use the same read and write grants', (
    tester,
  ) async {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final repository = api.instantiate(
      codingRepositoryKitId,
      origin: Offset.zero,
    );
    final selection = SelectionController()..select(repository.first);
    final readPermission = _InspectorRepositoryPermission();
    final writePermission = _InspectorWritePermission();
    final controller = AgentController(
      kitApi: api,
      session: AgentSession(model: FakeAgentModel(), kitApi: api),
      runtime: const ResolvedAgentRuntime(presetId: 'fake', useFake: true),
      repositoryPermission: readPermission,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(
            store: store,
            selection: selection,
            kitApi: api,
            controller: controller,
            writePermission: writePermission,
          ),
        ),
      ),
    );

    final readButton = find.byKey(const Key('choose-repository'));
    await tester.ensureVisible(readButton);
    await tester.tap(readButton);
    await tester.pump();
    expect(readPermission.chooseCalls, 1);
    expect(
      store.document.objectById(repository.first)!.props[repositoryPathProp],
      '/tmp/read-repo',
    );

    final writeButton = find.byKey(const Key('choose-repository-write'));
    await tester.ensureVisible(writeButton);
    await tester.tap(writeButton);
    await tester.pump();
    expect(writePermission.chooseCalls, 1);
    expect(
      store.document.objectById(repository.first)!.props[repositoryWritePathProp],
      '/tmp/write-repo',
    );
  });

  testWidgets('multi Inspector colors and deletes kits and cables', (
    tester,
  ) async {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final first = api.instantiate(boardTextKitId, origin: Offset.zero);
    final second = api.instantiate(
      boardTextKitId,
      origin: const Offset(0, 200),
    );
    final llm = api.instantiate(harnessLlmKitId, origin: const Offset(400, 0));
    connectTextToLlm(
      kitApi: api,
      textObjectId: first.first,
      llmBodyId: llm.last,
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: second.first,
      llmBodyId: llm.last,
      port: llmContextPort,
    );
    final cable = sceneCables(store.document)
        .singleWhere((item) => item.sourceId == first.first);
    final selection = SelectionController()
      ..selectMany(
        objectIds: {first.first, second.first},
        cableIds: {cable.id},
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection, kitApi: api),
        ),
      ),
    );
    expect(find.byKey(const Key('multi-selection-inspector')), findsOneWidget);
    expect(find.byKey(const Key('multi-selection-swatches')), findsOneWidget);

    final swatch = kitSwatches[2];
    await tester.tap(
      find.byKey(ValueKey('multi-swatch-${colorToHex(swatch)}')),
    );
    await tester.pump();
    expect(
      store.document.objectById(first.first)!.props[kitAccentProp],
      colorToHex(swatch),
    );
    expect(
      store.document.objectById(second.first)!.props[kitAccentProp],
      colorToHex(swatch),
    );
    expect(
      colorToHex(
        sceneCables(store.document)
            .singleWhere((item) => item.id == cable.id)
            .color,
      ),
      colorToHex(swatch),
    );

    await tester.tap(find.text('Delete selected'));
    await tester.pump();
    expect(store.document.objectById(first.first), isNull);
    expect(store.document.objectById(second.first), isNull);
    expect(store.document.objectById(llm.first), isNotNull);
    expect(selection.selectedIds, isEmpty);
    expect(selection.selectedCableIds, isEmpty);
    store.undo();
    expect(store.document.objectById(first.first), isNotNull);
    expect(store.document.objectById(second.first), isNotNull);
  });

  testWidgets('text content submit applies UpdateObjectProps; undo restores', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 't1',
          type: 'text',
          x: 0,
          y: 0,
          width: 80,
          height: 40,
          props: {'content': 'old', 'fontSize': 18, 'color': '#1B1B1B'},
        ),
      ),
    );
    final selection = SelectionController()..select('t1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('inspector-content')), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(store.document.objects.single.props['content'], 'hello');
    store.undo();
    expect(store.document.objects.single.props['content'], 'old');
  });

  testWidgets('slow content typing accumulates without select-all wipe', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 't1',
          type: 'text',
          x: 0,
          y: 0,
          width: 80,
          height: 40,
          props: {'content': 'old', 'fontSize': 18, 'color': '#1B1B1B'},
        ),
      ),
    );
    final selection = SelectionController()..select('t1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );

    final field = find.byKey(const Key('inspector-content'));
    await tester.tap(field);
    await tester.pump();

    await tester.enterText(field, 'h');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    EditableText editable() {
      return tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
    }

    expect(editable().controller.text, 'h');
    expect(editable().controller.selection.isCollapsed, isTrue);
    expect(editable().controller.selection.baseOffset, 1);

    await tester.enterText(field, 'he');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(field, 'hel');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(editable().controller.text, 'hel');
    expect(editable().controller.selection.isCollapsed, isTrue);
    expect(store.document.objects.single.props['content'], 'hel');
  });

  testWidgets('Delete button removes the object and clears selection', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 'b1',
          type: 'box',
          x: 0,
          y: 0,
          width: 80,
          height: 40,
        ),
      ),
    );
    final selection = SelectionController()..select('b1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(store.document.objects, isEmpty);
    expect(selection.selectedId, isNull);
  });

  testWidgets('Locked switch applies SetObjectLocked; undo restores', (
    tester,
  ) async {
    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 'b1',
          type: 'box',
          x: 0,
          y: 0,
          width: 80,
          height: 40,
        ),
      ),
    );
    final selection = SelectionController()..select('b1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(store.document.objects.single.locked, isTrue);
    store.undo();
    expect(store.document.objects.single.locked, isFalse);
  });

  testWidgets('kits omit Transform, including a future kit id', (tester) async {
    for (final kitId in [
      codingRepositoryKitId,
      boardTextKitId,
      harnessLlmKitId,
      'tools.read',
    ]) {
      final store = SceneStore();
      final kitApi = createAppKitApi(store: store);
      final ids = kitApi.instantiate(kitId, origin: Offset.zero);
      final selection = SelectionController()
        ..select(kitId == codingRepositoryKitId ? ids.last : ids.first);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectorPanel(
              key: ValueKey(kitId),
              store: store,
              selection: selection,
              kitApi: kitApi,
            ),
          ),
        ),
      );
      expect(find.text('Transform'), findsNothing, reason: kitId);
      expect(find.text('Locked'), findsNothing, reason: kitId);
    }

    final store = SceneStore();
    store.apply(
      AddObject(
        const SceneObject(
          id: 'future-kit',
          type: 'box',
          x: 0,
          y: 0,
          width: 100,
          height: 80,
          props: {skapieKitProp: 'example.future', skapieRoleProp: 'frame'},
        ),
      ),
    );
    final selection = SelectionController()..select('future-kit');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(store: store, selection: selection),
        ),
      ),
    );
    expect(find.text('Transform'), findsNothing);

    store.apply(
      AddObject(
        const SceneObject(
          id: 'standalone',
          type: 'box',
          x: 200,
          y: 0,
          width: 80,
          height: 60,
        ),
      ),
    );
    selection.select('standalone');
    await tester.pump();
    expect(find.text('Transform'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
  });

  testWidgets('allowed connection uses the LLM name and accent color', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    for (final id in llm) {
      kitApi.updateProps(id, {kitNameProp: 'Blue', kitAccentProp: '#88CCFF'});
    }
    final tool = kitApi.instantiate(
      'tools.read',
      origin: const Offset(400, 0),
    );
    final selection = SelectionController()..select(tool.last);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(
            store: store,
            selection: selection,
            kitApi: kitApi,
            lastLlmBodyId: llm.last,
          ),
        ),
      ),
    );

    Text nameText() => tester.widget<Text>(find.text('Blue'));
    expect(nameText().style?.color, const Color(0xFF88CCFF));
    final row = find.byKey(ValueKey('allowed-connection-${llm.last}'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);

    selection.select(llm.first);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('inspector-id')));
    await tester.enterText(find.byKey(const Key('inspector-id')), 'Sky');
    await tester.pump(const Duration(milliseconds: 250));
    selection.select(tool.last);
    await tester.pump();

    expect(find.text('Sky'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Sky')).style?.color,
      const Color(0xFF88CCFF),
    );
  });

  testWidgets('a kit swatch sets accent and the inspector has no fill field', (
    tester,
  ) async {
    final store = SceneStore();
    final kitApi = createAppKitApi(store: store);
    final llm = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final selection = SelectionController()..select(llm.first);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InspectorPanel(
            store: store,
            selection: selection,
            kitApi: kitApi,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('kit-swatches')), findsOneWidget);
    expect(find.byKey(const Key('inspector-fill')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('kit-swatch-#7EB6E8')));
    await tester.pump();
    expect(
      store.document.objectById(llm.first)!.props[kitAccentProp],
      '#7EB6E8',
    );
  });
}

class _InspectorRepositoryPermission implements RepositoryPermission {
  int chooseCalls = 0;

  @override
  Future<String?> chooseDirectory() async {
    chooseCalls++;
    return '/tmp/read-repo';
  }

  @override
  Future<bool> canRead(String path) async => true;
}

class _InspectorWritePermission implements PatchWritePermission {
  int chooseCalls = 0;

  @override
  Future<String?> chooseDirectory() async {
    chooseCalls++;
    return '/tmp/write-repo';
  }

  @override
  Future<bool> canWrite(String path) async => true;

  @override
  Future<String?> exportProposal({
    required String name,
    required String text,
  }) async => null;
}
