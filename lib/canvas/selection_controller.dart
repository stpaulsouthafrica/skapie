import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:skapie/scene/scene_document.dart';

/// UI-only selection and move preview. Not persisted on the scene.
class SelectionController extends ChangeNotifier {
  String? _selectedId;
  Offset _previewDelta = Offset.zero;
  bool _moving = false;
  double? _originX;
  double? _originY;

  String? get selectedId => _selectedId;
  Offset get previewDelta => _previewDelta;
  bool get isMoving => _moving;

  void select(String? id) {
    if (_selectedId == id && !_moving && _previewDelta == Offset.zero) {
      return;
    }
    _selectedId = id;
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
  }

  void syncToDocument(SceneDocument document) {
    final id = _selectedId;
    if (id != null && document.objectById(id) == null) {
      select(null);
    }
  }

  void beginMove({required double originX, required double originY}) {
    _moving = true;
    _originX = originX;
    _originY = originY;
    _previewDelta = Offset.zero;
    notifyListeners();
  }

  void updatePreview(Offset worldDelta) {
    if (!_moving) {
      return;
    }
    _previewDelta = worldDelta;
    notifyListeners();
  }

  ({double x, double y})? endMove() {
    if (!_moving || _originX == null || _originY == null) {
      _moving = false;
      _previewDelta = Offset.zero;
      notifyListeners();
      return null;
    }
    final changed = _previewDelta != Offset.zero;
    final commit = (
      x: _originX! + _previewDelta.dx,
      y: _originY! + _previewDelta.dy,
    );
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
    return changed ? commit : null;
  }

  void cancelMove() {
    if (!_moving) {
      return;
    }
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
  }
}
