import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  test('select and clear', () {
    final selection = SelectionController();
    selection.select('a');
    expect(selection.selectedId, 'a');
    selection.select(null);
    expect(selection.selectedId, isNull);
  });

  test('syncToDocument clears selection when id is missing', () {
    final selection = SelectionController()..select('gone');
    selection.syncToDocument(SceneDocument.empty());
    expect(selection.selectedId, isNull);
  });

  test('marquee can hold objects and cables without a misleading primary', () {
    final selection = SelectionController()
      ..selectMany(objectIds: {'a', 'b'}, cableIds: {'c'});
    expect(selection.selectedIds, {'a', 'b'});
    expect(selection.selectedCableIds, {'c'});
    expect(selection.isMultiple, isTrue);
    expect(selection.selectedId, isNull);
    expect(selection.selectedCableId, isNull);

    selection.select('a');
    expect(selection.selectedIds, {'a'});
    expect(selection.selectedCableIds, isEmpty);
    selection.selectMany(objectIds: {}, cableIds: {'c'});
    expect(selection.selectedCableId, 'c');
    selection.syncToDocument(SceneDocument.empty(), cableIds: {});
    expect(selection.selectedCableIds, isEmpty);
  });

  test('endMove commits one preview offset from origin', () {
    final selection = SelectionController()..select('a');
    selection.beginMove(originX: 10, originY: 20);
    selection.updatePreview(const Offset(4, -3));
    final commit = selection.endMove();
    expect(commit, (x: 14.0, y: 17.0));
    expect(selection.previewDelta, Offset.zero);
    expect(selection.isMoving, isFalse);
  });

  test('cancelMove discards preview without a commit', () {
    final selection = SelectionController()..select('a');
    selection.beginMove(originX: 10, originY: 20);
    selection.updatePreview(const Offset(8, 8));
    selection.cancelMove();
    expect(selection.previewDelta, Offset.zero);
    expect(selection.isMoving, isFalse);
    expect(selection.selectedId, 'a');
  });

  test('endMove with zero delta does not commit', () {
    final selection = SelectionController()..select('a');
    selection.beginMove(originX: 1, originY: 2);
    expect(selection.endMove(), isNull);
  });
}
