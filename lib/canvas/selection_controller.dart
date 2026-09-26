import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:skapie/canvas/kit_port_descriptor.dart';
import 'package:skapie/scene/scene_document.dart';

/// UI-only selection and move preview. Not persisted on the scene.
class SelectionController extends ChangeNotifier {
  final Set<String> _selectedIds = {};
  final Set<String> _selectedCableIds = {};
  Offset _previewDelta = Offset.zero;
  bool _moving = false;
  double? _originX;
  double? _originY;

  KitPortKind? _selectedPort;

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  Set<String> get selectedCableIds => Set.unmodifiable(_selectedCableIds);
  bool get isMultiple => _selectedIds.length + _selectedCableIds.length > 1;
  String? get selectedId =>
      _selectedIds.length == 1 && _selectedCableIds.isEmpty
      ? _selectedIds.single
      : null;

  /// Port ringed on the selected kit. Cleared with the kit.
  KitPortKind? get selectedPort => selectedId == null ? null : _selectedPort;

  /// A [SceneCable.id] when exactly one cable is selected.
  String? get selectedCableId =>
      _selectedCableIds.length == 1 && _selectedIds.isEmpty
      ? _selectedCableIds.single
      : null;
  Offset get previewDelta => _previewDelta;
  bool get isMoving => _moving;

  void selectCable(String? id) {
    if (selectedCableId == id &&
        _selectedIds.isEmpty &&
        _selectedCableIds.length == (id == null ? 0 : 1)) {
      return;
    }
    _selectedCableIds
      ..clear()
      ..addAll(id == null ? const <String>{} : {id});
    _selectedIds.clear();
    _selectedPort = null;
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
  }

  void select(String? id) {
    if (selectedId == id &&
        _selectedCableIds.isEmpty &&
        _selectedIds.length == (id == null ? 0 : 1) &&
        !_moving &&
        _previewDelta == Offset.zero) {
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(id == null ? const <String>{} : {id});
    _selectedCableIds.clear();
    _selectedPort = null;
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
  }

  /// Replace the transient selection with everything crossed by a marquee.
  void selectMany({
    required Set<String> objectIds,
    required Set<String> cableIds,
  }) {
    if (setEquals(_selectedIds, objectIds) &&
        setEquals(_selectedCableIds, cableIds) &&
        _selectedPort == null &&
        !_moving &&
        _previewDelta == Offset.zero) {
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(objectIds);
    _selectedCableIds
      ..clear()
      ..addAll(cableIds);
    _selectedPort = null;
    _moving = false;
    _previewDelta = Offset.zero;
    _originX = null;
    _originY = null;
    notifyListeners();
  }

  /// Ring [kind] on the selected kit. No kit selected means no ring.
  void selectPort(KitPortKind? kind) {
    if (selectedId == null || _selectedPort == kind) {
      return;
    }
    _selectedPort = kind;
    notifyListeners();
  }

  void syncToDocument(SceneDocument document, {Set<String>? cableIds}) {
    final before = _selectedIds.length + _selectedCableIds.length;
    _selectedIds.removeWhere((id) => document.objectById(id) == null);
    if (cableIds != null) {
      _selectedCableIds.removeWhere((id) => !cableIds.contains(id));
    }
    if (_selectedIds.length + _selectedCableIds.length != before) {
      _selectedPort = null;
      notifyListeners();
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
