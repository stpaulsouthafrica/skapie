import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/cable_layer.dart';
import 'package:skapie/canvas/canvas_bounds.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_grid_painter.dart';
import 'package:skapie/canvas/hit_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/scene_object_layer.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/canvas/selection_overlay.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

/// Infinite canvas viewport: pan, zoom-toward-cursor, grid, origin, zoom HUD.
class CanvasViewport extends StatefulWidget {
  CanvasViewport({
    super.key,
    required this.store,
    SelectionController? selection,
    ObjectRegistry? registry,
    KitApi? kitApi,
  }) : selection = selection ?? SelectionController(),
       kitApi =
           kitApi ??
           KitApi(store: store, registry: registry ?? createBuiltinRegistry());

  final SceneStore store;
  final SelectionController selection;
  final KitApi kitApi;
  ObjectRegistry get registry => kitApi.registry;

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
  final _inlineController = TextEditingController();
  final _inlineFocus = FocusNode();
  String? _inlineEditId;
  String? _cableFrameId;
  KitPortKind? _cableKind;
  Offset? _cableCursor;
  Duration? _lastTapStamp;
  String? _lastTapId;

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
    _inlineFocus.dispose();
    _inlineController.dispose();
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

  void addDebugRect() => addTypedObject(debugRectType);

  void addTypedObject(String typeId) {
    final size = defaultObjectSize(typeId);
    final center = _camera.offset;
    widget.kitApi.addObject(
      typeId: typeId,
      x: center.dx - size.width / 2,
      y: center.dy - size.height / 2,
    );
  }

  void instantiateKit(String kitId) {
    widget.kitApi.instantiate(kitId, origin: _camera.offset);
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
    _dragPointer = event.pointer;
    _lastDrag = event.localPosition;
    if (middle) {
      _dragKind = _DragKind.pan;
      _focus.requestFocus();
      return;
    }
    if (_viewportSize.isEmpty) {
      _dragKind = _DragKind.pan;
      _focus.requestFocus();
      return;
    }
    final world = screenToWorld(event.localPosition, _viewportSize, _camera);
    final port = hitKitPort(kitPorts(widget.store.document), world);
    if (port != null && kitPortIsOutput(port.kind)) {
      _focus.requestFocus();
      widget.selection.select(port.frameId);
      _dragKind = _DragKind.cable;
      _cableFrameId = port.frameId;
      _cableKind = port.kind;
      _cableCursor = world;
      setState(() {});
      return;
    }
    final hit = hitTestObjects(widget.store.document.objects, world);
    if (_inlineEditId != null) {
      if (hit?.id == _inlineEditId) {
        _dragKind = _DragKind.none;
        return;
      }
      _commitInlineEdit();
    }
    _focus.requestFocus();
    if (hit == null) {
      widget.selection.select(null);
      _dragKind = _DragKind.pan;
      return;
    }
    widget.selection.select(hit.id);
    final isDouble =
        hit.id == _lastTapId &&
        _lastTapStamp != null &&
        event.timeStamp - _lastTapStamp! <= kDoubleTapTimeout;
    _lastTapId = hit.id;
    _lastTapStamp = event.timeStamp;
    if (isDouble) {
      final edit = _inlineEditTarget(hit);
      if (edit != null) {
        widget.selection.cancelMove();
        _dragKind = _DragKind.none;
        _beginInlineEdit(edit);
        return;
      }
    }
    final movers = _moveMembers(hit);
    if (movers.every(objectAllowsMove)) {
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
      return;
    }
    if (_dragKind == _DragKind.cable) {
      setState(() {
        _cableCursor = screenToWorld(
          event.localPosition,
          _viewportSize,
          _camera,
        );
      });
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    final up = event is PointerUpEvent ? event.localPosition : _lastDrag;
    _finishPointer(commitMove: true, upLocal: up);
  }

  void _onPointerCancel(PointerEvent event) {
    if (event.pointer != _dragPointer) {
      return;
    }
    _finishPointer(commitMove: false);
  }

  void _finishPointer({required bool commitMove, Offset? upLocal}) {
    final kind = _dragKind;
    final cableFrame = _cableFrameId;
    final cableKind = _cableKind;
    _dragPointer = null;
    _lastDrag = null;
    _moveWorldStart = null;
    _dragKind = _DragKind.none;
    _cableFrameId = null;
    _cableKind = null;
    _cableCursor = null;
    if (kind == _DragKind.cable) {
      if (commitMove &&
          upLocal != null &&
          cableFrame != null &&
          cableKind != null) {
        _completeCable(cableFrame, cableKind, upLocal);
      }
      setState(() {});
      return;
    }
    if (kind != _DragKind.move) {
      return;
    }
    if (!commitMove) {
      widget.selection.cancelMove();
      return;
    }
    final delta = widget.selection.previewDelta;
    final commit = widget.selection.endMove();
    final id = widget.selection.selectedId;
    if (commit == null || id == null) {
      return;
    }
    final selected = widget.store.document.objectById(id);
    if (selected == null) {
      return;
    }
    final members = _moveMembers(selected);
    for (final member in members) {
      widget.kitApi.updateFrame(
        id: member.id,
        x: member.x + delta.dx,
        y: member.y + delta.dy,
      );
    }
  }

  void _completeCable(String frameId, KitPortKind sourceKind, Offset upLocal) {
    final world = screenToWorld(upLocal, _viewportSize, _camera);
    final port = hitKitPort(kitPorts(widget.store.document), world);
    if (port == null || !kitPortAccepts(sourceKind, port.kind)) {
      return;
    }
    final source = widget.store.document.objectById(frameId);
    if (source == null) {
      return;
    }
    if (sourceKind == KitPortKind.llmOutput) {
      final sourcePort = kitPorts(widget.store.document)
          .where(
            (item) =>
                item.frameId == frameId && item.kind == KitPortKind.llmOutput,
          )
          .firstOrNull;
      if (sourcePort == null || sourcePort.peerId == port.peerId) {
        return;
      }
      connectLlmOutput(
        kitApi: widget.kitApi,
        sourceBodyId: sourcePort.peerId,
        targetBodyId: port.peerId,
        port: port.kind == KitPortKind.llmContext
            ? llmContextPort
            : llmInputPort,
      );
      return;
    }
    if (sourceKind == KitPortKind.toolOut) {
      attachToolKit(
        kitApi: widget.kitApi,
        toolObjectId: frameId,
        llmBodyId: port.peerId,
      );
      return;
    }
    connectTextToLlm(
      kitApi: widget.kitApi,
      textObjectId: frameId,
      llmBodyId: port.peerId,
      port: port.kind == KitPortKind.llmContext ? llmContextPort : llmInputPort,
    );
  }

  List<SceneObject> _moveMembers(SceneObject hit) {
    return kitMembers(document: widget.store.document, selectedId: hit.id) ??
        [hit];
  }

  Set<String> get _previewIds {
    final id = widget.selection.selectedId;
    if (id == null || !widget.selection.isMoving) {
      return const {};
    }
    final selected = widget.store.document.objectById(id);
    if (selected == null) {
      return {id};
    }
    return {for (final member in _moveMembers(selected)) member.id};
  }

  void _clearSelectionOrCancelMove() {
    if (_inlineEditId != null) {
      _commitInlineEdit();
      return;
    }
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
    removeKitSelection(kitApi: widget.kitApi, selectedId: id);
    widget.selection.syncToDocument(widget.store.document);
  }

  bool _canInlineEdit(SceneObject object) {
    if (object.type != textTypeId) {
      return false;
    }
    if (isLlmKitObject(object)) {
      return false;
    }
    return object.props[skapieRoleProp] != 'grant';
  }

  SceneObject? _inlineEditTarget(SceneObject hit) {
    if (_canInlineEdit(hit)) {
      return hit;
    }
    if (hit.props[skapieRoleProp] != 'frame' ||
        kitIdOf(hit) != boardTextKitId) {
      return null;
    }
    for (final object in widget.store.document.objects) {
      if (object.type == textTypeId &&
          kitIdOf(object) == boardTextKitId &&
          kitChildBelongsToFrame(object, hit)) {
        return object;
      }
    }
    return null;
  }

  void _beginInlineEdit(SceneObject object) {
    final content = object.props['content']?.toString() ?? '';
    _inlineEditId = object.id;
    _inlineController.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: content.length),
    );
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inlineFocus.requestFocus();
      }
    });
  }

  void _commitInlineEdit() {
    final id = _inlineEditId;
    if (id == null) {
      return;
    }
    widget.kitApi.updateProps(id, {'content': _inlineController.text});
    _inlineEditId = null;
    _inlineFocus.unfocus();
    setState(() {});
    _focus.requestFocus();
  }

  Widget? _inlineEditor(Size viewportSize) {
    final id = _inlineEditId;
    if (id == null) {
      return null;
    }
    final object = widget.store.document.objectById(id);
    if (object == null) {
      return null;
    }
    final tokens = PaintScope.of(context);
    final topLeft = worldToScreen(
      Offset(object.x, object.y),
      viewportSize,
      _camera,
    );
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: math.max(48, object.width * _camera.zoom),
      height: math.max(28, object.height * _camera.zoom),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _commitInlineEdit,
        },
        child: Material(
          color: tokens.panel,
          child: TextField(
            key: const Key('inline-text-edit'),
            controller: _inlineController,
            focusNode: _inlineFocus,
            autofocus: true,
            maxLines: null,
            style: TextStyle(color: tokens.ink, fontSize: 13),
            cursorColor: tokens.accent,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            ),
            onSubmitted: (_) => _commitInlineEdit(),
            onTapOutside: (_) => _commitInlineEdit(),
          ),
        ),
      ),
    );
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
                    CableLayer(
                      camera: _camera,
                      viewportSize: size,
                      document: widget.store.document,
                      previewDelta: widget.selection.previewDelta,
                      previewIds: _previewIds,
                    ),
                    SceneObjectLayer(
                      camera: _camera,
                      viewportSize: size,
                      objects: objects,
                      registry: widget.registry,
                      selectedId: widget.selection.selectedId,
                      previewDelta: widget.selection.previewDelta,
                      previewIds: _previewIds,
                    ),
                    if (_cableFrameId != null && _cableCursor != null)
                      CableLayer(
                        camera: _camera,
                        viewportSize: size,
                        document: widget.store.document,
                        dragFrameId: _cableFrameId,
                        dragKind: _cableKind,
                        dragCursor: _cableCursor,
                        previewOnly: true,
                      ),
                    if (_selectedObject != null &&
                        !isKitObject(_selectedObject!))
                      SceneSelectionOverlay(
                        camera: _camera,
                        viewportSize: size,
                        object: _selectedObject!,
                        previewDelta: widget.selection.previewDelta,
                      ),
                    ?_inlineEditor(size),
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

enum _DragKind { none, pan, move, cable }
