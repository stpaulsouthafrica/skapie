import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:skapie/canvas/kit_port_descriptor.dart';
import 'package:skapie/scene/scene_document.dart';

/// UI-only selection and move preview. Not persisted on the scene.
class SelectionController extends ChangeNotifier {
  String? _selectedId;
  Offset _previewDelta = Offset.zero;
  bool _moving = false;
  double? _originX;
  double? _originY;

  String? _selectedCableId;
  KitPortKind? _selectedPort;

  String? get selectedId => _selectedId;

  /// Port ringed on the selected kit. Cleared with the kit.
  KitPortKind? get selectedPort => _selectedId == null ? null : _selectedPort;

  /// A [SceneCable.id]. Only one of object or cable is selected at a time.
  String? get selectedCableId => _selectedCableId;
  Offset get previewDelta => _previewDelta;
  bool get isMoving => _moving;

  void selectCable(String? id) {
    if (_selectedCableId == id && _selectedId == null) {
      return;
    }
    _selectedCableId = id;
    _selectedId = null;
    _selectedPort = null;
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
  }

  void select(String? id) {
    if (_selectedId == id &&
        _selectedCableId == null &&
        !_moving &&
        _previewDelta == Offset.zero) {
      return;
    }
    _selectedCableId = null;
    _selectedId = id;
    _selectedPort = null;
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
  }

  /// Ring [kind] on the selected kit. No kit selected means no ring.
  void selectPort(KitPortKind? kind) {
    if (_selectedId == null || _selectedPort == kind) {
      return;
    }
    _selectedPort = kind;
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
