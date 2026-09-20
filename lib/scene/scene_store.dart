import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:skapie/scene/scene_document.dart';
import 'package:skapie/scene/scene_object.dart';
import 'package:skapie/scene/scene_op.dart';
import 'package:skapie/scene/scene_persistence.dart';

/// Single mutation path for the scene document.
class SceneStore extends ChangeNotifier {
  SceneStore({SceneDocument? document, this.persistence})
    : _document = document ?? SceneDocument.empty();

  final SceneFilePersistence? persistence;

  SceneDocument _document;
  final List<SceneDocument> _undo = [];
  final List<SceneDocument> _redo = [];
  SceneCameraSnapshot? _liveCamera;
  Future<void> _writes = Future.value();

  Object? _lastPersistenceError;

  SceneDocument get document => _document;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  Object? get lastPersistenceError => _lastPersistenceError;
  String? get sceneFilePath => persistence?.absolutePath;

  /// Remember the live viewport camera for the next save. Not undoable.
  void noteCamera(SceneCameraSnapshot snapshot) {
    _liveCamera = snapshot;
  }

  /// Apply [op] or no-op if it would not change the document.
  bool apply(SceneOp op) {
    final next = op.apply(_document);
    if (next == _document) {
      return false;
    }
    _undo.add(_document);
    _redo.clear();
    _document = next;
    notifyListeners();
    unawaited(save());
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    _redo.add(_document);
    _document = _undo.removeLast();
    notifyListeners();
    unawaited(save());
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) {
      return false;
    }
    _undo.add(_document);
    _document = _redo.removeLast();
    notifyListeners();
    unawaited(save());
    return true;
  }

  Future<void> load() async {
    final loaded = await persistence?.read();
    _document = loaded ?? SceneDocument.empty();
    _undo.clear();
    _redo.clear();
    _liveCamera = _document.camera;
    notifyListeners();
  }

  Future<void> save() {
    final done = Completer<void>();
    final previous = _writes;
    _writes = done.future;
    return previous
        .then((_) async {
          final persistence = this.persistence;
          if (persistence == null) {
            return;
          }
          if (_liveCamera != null) {
            _document = _document.copyWith(camera: _liveCamera);
          }
          try {
            await persistence.write(_document);
            if (_lastPersistenceError != null) {
              _lastPersistenceError = null;
              notifyListeners();
            }
          } catch (error, stack) {
            _lastPersistenceError = error;
            debugPrint('Skapie scene save failed ($error)\n$stack');
            notifyListeners();
          }
        })
        .whenComplete(done.complete);
  }
}
