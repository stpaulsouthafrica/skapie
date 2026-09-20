import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_grid_painter.dart';
import 'package:skapie/canvas/debug_node_painter.dart';
import 'package:skapie/scene/scene.dart';

/// Infinite canvas viewport: pan, zoom-toward-cursor, grid, origin, zoom HUD.
class CanvasViewport extends StatefulWidget {
  const CanvasViewport({super.key, required this.store});

  final SceneStore store;

  @override
  State<CanvasViewport> createState() => CanvasViewportState();
}

class CanvasViewportState extends State<CanvasViewport> {
  late CanvasCamera _camera = _cameraFrom(widget.store.document.camera);
  int? _dragPointer;
  Offset? _lastDrag;
  CanvasCamera? _panZoomStart;

  String get _zoomLabel => '${(_camera.zoom * 100).round()}%';

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
    widget.store.noteCamera(_snapshot(_camera));
  }

  @override
  void didUpdateWidget(CanvasViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() => setState(() {});

  void _setCamera(CanvasCamera next) {
    if (next == _camera) {
      return;
    }
    setState(() => _camera = next);
    widget.store.noteCamera(_snapshot(next));
  }

  void resetCamera() => _setCamera(_camera.reset());

  void addDebugRect() {
    const width = 120.0;
    const height = 80.0;
    final center = _camera.offset;
    widget.store.apply(
      AddNode(
        SceneNode(
          id: newSceneId('n'),
          type: debugRectType,
          x: center.dx - width / 2,
          y: center.dy - height / 2,
          width: width,
          height: height,
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _dragPointer = event.pointer;
      _lastDrag = event.localPosition;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer || _lastDrag == null) {
      return;
    }
    final delta = event.localPosition - _lastDrag!;
    _lastDrag = event.localPosition;
    _setCamera(_camera.panScreen(delta));
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer == _dragPointer) {
      _dragPointer = null;
      _lastDrag = null;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final size = context.size;
    if (size == null) {
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
    final size = context.size;
    if (start == null || size == null) {
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
    final nodes = widget.store.document.nodes;

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
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            widget.store.redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): widget.store.redo,
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
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
                    child: CustomPaint(
                      painter: DebugNodePainter(
                        camera: _camera,
                        nodes: nodes,
                        fillColor: colors.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                        strokeColor: colors.outline,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
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
  }
}
