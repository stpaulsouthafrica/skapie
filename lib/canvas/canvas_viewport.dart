import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/canvas/canvas_bounds.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_grid_painter.dart';
import 'package:skapie/canvas/hit_test.dart';
import 'package:skapie/canvas/scene_object_layer.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/canvas/selection_overlay.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

/// Infinite canvas viewport: pan, zoom-toward-cursor, grid, origin, zoom HUD.
class CanvasViewport extends StatefulWidget {
  CanvasViewport({
    super.key,
    required this.store,
    SelectionController? selection,
    ObjectRegistry? registry,
  }) : registry = registry ?? createBuiltinRegistry(),
       selection = selection ?? SelectionController();

  final SceneStore store;
  final SelectionController selection;
  final ObjectRegistry registry;

  @override
  State<CanvasViewport> createState() => CanvasViewportState();
}

class CanvasViewportState extends State<CanvasViewport> {
  late CanvasCamera _camera = _cameraFrom(widget.store.document.camera);
  int? _dragPointer;
  Offset? _lastDrag;
  CanvasCamera? _panZoomStart;
  _DragKind _dragKind = _DragKind.none;
  Offset? _moveWorldStart;
  final _focus = FocusNode();

  Size _viewportSize = Size.zero;

  CanvasCamera get camera => _camera;

  String get _zoomLabel => '${(_camera.zoom * 100).round()}%';

  SceneObject? get _selectedObject {
    final id = widget.selection.selectedId;
    if (id == null) {
      return null;
    }
    return widget.store.document.objectById(id);
  }

  static CanvasCamera _cameraFrom(SceneCameraSnapshot? snapshot) {
    if (snapshot == null) {
      return CanvasCamera();
    }
    return CanvasCamera(
      offset: Offset(snapshot.offsetX, snapshot.offsetY),
      zoom: snapshot.zoom,
    );
  }

  static SceneCameraSnapshot _snapshot(CanvasCamera camera) {
    return SceneCameraSnapshot(
      offsetX: camera.offset.dx,
      offsetY: camera.offset.dy,
      zoom: camera.zoom,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    widget.selection.addListener(_onSelection);
    widget.store.noteCamera(_snapshot(_camera));
  }

  @override
  void didUpdateWidget(CanvasViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
    }
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelection);
      widget.selection.addListener(_onSelection);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    widget.selection.removeListener(_onSelection);
    _focus.dispose();
    super.dispose();
  }

  void _onSelection() => setState(() {});

  void _onStore() {
    widget.selection.syncToDocument(widget.store.document);
    final next = _clamped(_camera);
    setState(() => _camera = next);
    widget.store.noteCamera(_snapshot(next));
  }

  CanvasCamera _clamped(CanvasCamera camera) {
    return clampCameraToContent(
      camera: camera,
      viewportSize: _viewportSize,
      objects: widget.store.document.objects,
    );
  }

  void _setCamera(CanvasCamera next) {
    next = _clamped(next);
    if (next == _camera) {
      return;
    }
    setState(() => _camera = next);
    widget.store.noteCamera(_snapshot(next));
  }

  void resetCamera() => _setCamera(_camera.reset());

  static const _defaultSizes = {
    boxTypeId: Size(160, 100),
    textTypeId: Size(220, 48),
    buttonTypeId: Size(140, 40),
    debugRectType: Size(120, 80),
  };

  void addDebugRect() => addTypedObject(debugRectType);

  void addTypedObject(String typeId) {
    final type = widget.registry.get(typeId);
    if (type == null) {
      return;
    }
    final size = _defaultSizes[typeId] ?? const Size(120, 80);
    final center = _camera.offset;
    widget.store.apply(
      AddObject(
        SceneObject(
          id: newSceneId('o'),
          type: typeId,
          x: center.dx - size.width / 2,
          y: center.dy - size.height / 2,
          width: size.width,
          height: size.height,
          props: Map<String, Object?>.of(type.defaultProps),
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.trackpad) {
      return;
    }
    final middle =
        event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kMiddleMouseButton) != 0;
    if (event.kind == PointerDeviceKind.mouse &&
        !middle &&
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    _focus.requestFocus();
    _dragPointer = event.pointer;
    _lastDrag = event.localPosition;
    if (middle) {
      _dragKind = _DragKind.pan;
      return;
    }
    if (_viewportSize.isEmpty) {
      _dragKind = _DragKind.pan;
      return;
    }
    final world = screenToWorld(event.localPosition, _viewportSize, _camera);
    final hit = hitTestObjects(widget.store.document.objects, world);
    if (hit == null) {
      widget.selection.select(null);
      _dragKind = _DragKind.pan;
      return;
    }
    widget.selection.select(hit.id);
    if (objectAllowsMove(hit)) {
      _dragKind = _DragKind.move;
      _moveWorldStart = world;
      widget.selection.beginMove(originX: hit.x, originY: hit.y);
    } else {
      _dragKind = _DragKind.none;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer || _lastDrag == null) {
      return;
    }
    if (_dragKind == _DragKind.pan) {
      final delta = event.localPosition - _lastDrag!;
      _lastDrag = event.localPosition;
      _setCamera(_camera.panScreen(delta));
      return;
    }
    if (_dragKind == _DragKind.move && _moveWorldStart != null) {
      final world = screenToWorld(event.localPosition, _viewportSize, _camera);
      widget.selection.updatePreview(world - _moveWorldStart!);
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    _finishPointer(commitMove: true);
  }

  void _onPointerCancel(PointerEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    _finishPointer(commitMove: false);
  }

  void _finishPointer({required bool commitMove}) {
    _dragPointer = null;
    _lastDrag = null;
    _moveWorldStart = null;
    final kind = _dragKind;
    _dragKind = _DragKind.none;
    if (kind != _DragKind.move) {
      return;
    }
    if (!commitMove) {
      widget.selection.cancelMove();
      return;
    }
    final commit = widget.selection.endMove();
    final id = widget.selection.selectedId;
    if (commit == null || id == null) {
      return;
    }
    widget.store.apply(UpdateObjectFrame(id: id, x: commit.x, y: commit.y));
  }

  void _clearSelectionOrCancelMove() {
    if (widget.selection.isMoving) {
      widget.selection.cancelMove();
      _dragPointer = null;
      _lastDrag = null;
      _moveWorldStart = null;
      _dragKind = _DragKind.none;
      return;
    }
    widget.selection.select(null);
  }

  void _deleteSelected() {
    if (widget.selection.isMoving) {
      return;
    }
    final id = widget.selection.selectedId;
    if (id == null) {
      return;
    }
    widget.store.apply(RemoveObject(id));
    widget.selection.syncToDocument(widget.store.document);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final size = _viewportSize;
    if (size.isEmpty) {
      return;
    }
    if (event.kind == PointerDeviceKind.trackpad) {
      _setCamera(_camera.panScreen(-event.scrollDelta));
      return;
    }
    final factor = math.pow(2, -event.scrollDelta.dy / 240).toDouble();
    _setCamera(
      _camera.zoomAt(
        cursor: event.localPosition,
        viewportSize: size,
        factor: factor,
      ),
    );
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomStart = _camera;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final start = _panZoomStart;
    final size = _viewportSize;
    if (start == null || size.isEmpty) {
      return;
    }
    var next = start.panScreen(event.pan);
    next = next.zoomAt(
      cursor: event.localPosition,
      viewportSize: size,
      zoom: start.zoom * event.scale,
    );
    _setCamera(next);
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomStart = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final objects = widget.store.document.objects;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _viewportSize) {
          _viewportSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _setCamera(_camera);
            }
          });
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.digit0): resetCamera,
            const SingleActivator(LogicalKeyboardKey.digit0, meta: true):
                resetCamera,
            const SingleActivator(LogicalKeyboardKey.digit0, control: true):
                resetCamera,
            const SingleActivator(LogicalKeyboardKey.numpad0): resetCamera,
            const SingleActivator(LogicalKeyboardKey.keyN): addDebugRect,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                widget.store.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                widget.store.undo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ): widget.store.redo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ): widget.store.redo,
            const SingleActivator(LogicalKeyboardKey.escape):
                _clearSelectionOrCancelMove,
            const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
            const SingleActivator(LogicalKeyboardKey.backspace):
                _deleteSelected,
          },
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              onPointerSignal: _onPointerSignal,
              onPointerPanZoomStart: _onPanZoomStart,
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              onPointerPanZoomEnd: _onPanZoomEnd,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: colors.surface,
                      child: CustomPaint(
                        painter: CanvasGridPainter(
                          camera: _camera,
                          dotColor: colors.outlineVariant,
                          originColor: colors.primary,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    SceneObjectLayer(
                      camera: _camera,
                      viewportSize: size,
                      objects: objects,
                      registry: widget.registry,
                      selectedId: widget.selection.selectedId,
                      previewDelta: widget.selection.previewDelta,
                    ),
                    if (_selectedObject != null)
                      SceneSelectionOverlay(
                        camera: _camera,
                        viewportSize: size,
                        object: _selectedObject!,
                        previewDelta: widget.selection.previewDelta,
                      ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Text(
                        _zoomLabel,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _DragKind { none, pan, move }
