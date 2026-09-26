import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_actions.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

void main() {
  test(
    'group move keeps kit members together, skips locked kits, undoes once',
    () {
      final store = SceneStore();
      final api = createAppKitApi(store: store);
      final first = api.instantiate(boardTextKitId, origin: Offset.zero);
      final second = api.instantiate(
        boardTextKitId,
        origin: const Offset(300, 0),
      );
      api.setLocked(second.first, true);
      final before = {
        for (final object in store.document.objects)
          object.id: Offset(object.x, object.y),
      };

      expect(
        moveSelection(
          store: store,
          objectIds: {first.first, second.first},
          delta: const Offset(45, -20),
        ),
        isTrue,
      );
      for (final id in first) {
        final moved = store.document.objectById(id)!;
        expect(Offset(moved.x, moved.y), before[id]! + const Offset(45, -20));
      }
      for (final id in second) {
        final still = store.document.objectById(id)!;
        expect(Offset(still.x, still.y), before[id]);
      }
      store.undo();
      for (final object in store.document.objects) {
        expect(Offset(object.x, object.y), before[object.id]);
      }
    },
  );

  test('group color changes only selected cable and kit, with one undo', () {
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
    final cables = sceneCables(store.document);
    expect(cables, hasLength(2));
    final selected = cables.singleWhere(
      (cable) => cable.sourceId == first.first,
    );
    final unselected = cables.singleWhere(
      (cable) => cable.sourceId == second.first,
    );
    final originalColor = unselected.color;
    const chosen = Colors.pink;

    expect(
      colorSelection(
        store: store,
        objectIds: {first.first},
        cableIds: {selected.id},
        color: chosen,
      ),
      isTrue,
    );
    expect(
      store.document.objectById(first.first)!.props[kitAccentProp],
      colorToHex(chosen),
    );
    final recolored = sceneCables(store.document);
    expect(
      colorToHex(
        recolored.singleWhere((cable) => cable.id == selected.id).color,
      ),
      colorToHex(chosen),
    );
    expect(
      recolored.singleWhere((cable) => cable.id == unselected.id).color,
      originalColor,
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: first.first,
      llmBodyId: llm.last,
      port: llmContextPort,
    );
    expect(
      colorToHex(
        sceneCables(store.document)
            .singleWhere((cable) => cable.id == selected.id)
            .color,
      ),
      colorToHex(chosen),
    );
    store.undo(); // Remove the extra link before undoing the group color.
    store.undo();
    expect(
      store.document.objectById(first.first)!.props[kitAccentProp],
      isNot(colorToHex(chosen)),
    );
    expect(
      sceneCables(store.document)
          .singleWhere((cable) => cable.id == selected.id)
          .color,
      originalColor,
    );
  });

  test('group delete refreshes a surviving LLM tool label in one undo', () {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final tool = api.instantiate(
      'tools.list_kits',
      origin: const Offset(400, 0),
    );
    final text = api.instantiate(boardTextKitId, origin: const Offset(800, 0));
    attachToolKit(kitApi: api, toolObjectId: tool.first, llmBodyId: llm.last);
    expect(
      store.document.objectById(llm.last)!.props['content'],
      contains('Tools: list_kits'),
    );

    expect(
      deleteSelection(
        store: store,
        objectIds: {tool.first, text.first},
        cableIds: {},
      ),
      isTrue,
    );
    expect(store.document.objectById(tool.first), isNull);
    expect(store.document.objectById(text.first), isNull);
    expect(
      store.document.objectById(llm.last)!.props['content'],
      contains('Tools: none'),
    );
    store.undo();
    expect(store.document.objectById(tool.first), isNotNull);
    expect(store.document.objectById(text.first), isNotNull);
    expect(
      store.document.objectById(llm.last)!.props['content'],
      contains('Tools: list_kits'),
    );
  });

  test('cable-only group actions leave unselected links alone', () {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final text = api.instantiate(boardTextKitId, origin: Offset.zero);
    final firstLlm = api.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final secondLlm = api.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 280),
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: text.first,
      llmBodyId: firstLlm.last,
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: text.first,
      llmBodyId: firstLlm.last,
      port: llmContextPort,
    );
    connectTextToLlm(
      kitApi: api,
      textObjectId: text.first,
      llmBodyId: secondLlm.last,
    );
    final before = sceneCables(store.document);
    expect(before, hasLength(3));
    final selectedIds = {
      for (final cable in before)
        if (cable.targetBodyId == firstLlm.last) cable.id,
    };
    expect(selectedIds, hasLength(2));
    final remaining = before.singleWhere(
      (cable) => cable.targetBodyId == secondLlm.last,
    );
    final oldColor = remaining.color;

    colorSelection(
      store: store,
      objectIds: {},
      cableIds: selectedIds,
      color: Colors.pink,
    );
    final colored = sceneCables(store.document);
    expect(
      colored
          .where((cable) => selectedIds.contains(cable.id))
          .every((cable) => colorToHex(cable.color) == colorToHex(Colors.pink)),
      isTrue,
    );
    expect(
      colored.singleWhere((cable) => cable.id == remaining.id).color,
      oldColor,
    );

    deleteSelection(store: store, objectIds: {}, cableIds: selectedIds);
    expect(sceneCables(store.document).map((cable) => cable.id), [
      remaining.id,
    ]);
    expect(store.document.objectById(text.first), isNotNull);
    store.undo();
    expect(sceneCables(store.document), hasLength(3));
  });

  test(
    'group delete removes selected kits and cables, then one undo restores',
    () {
      final store = SceneStore();
      final api = createAppKitApi(store: store);
      final first = api.instantiate(boardTextKitId, origin: Offset.zero);
      final second = api.instantiate(
        boardTextKitId,
        origin: const Offset(0, 200),
      );
      final llm = api.instantiate(
        harnessLlmKitId,
        origin: const Offset(400, 0),
      );
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
      final before = store.document.toJson();
      final secondCable = sceneCables(store.document)
          .singleWhere((cable) => cable.sourceId == second.first);

      expect(
        deleteSelection(
          store: store,
          objectIds: {first.first},
          cableIds: {secondCable.id},
        ),
        isTrue,
      );
      expect(store.document.objectById(first.first), isNull);
      expect(store.document.objectById(first.last), isNull);
      expect(store.document.objectById(second.first), isNotNull);
      expect(store.document.objectById(llm.first), isNotNull);
      expect(sceneCables(store.document), isEmpty);
      store.undo();
      expect(store.document.toJson(), before);
      expect(sceneCables(store.document), hasLength(2));
    },
  );
}
