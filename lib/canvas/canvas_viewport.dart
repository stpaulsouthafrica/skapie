import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_grid_painter.dart';

/// Infinite canvas viewport: pan, zoom-toward-cursor, grid, origin, zoom HUD.
class CanvasViewport extends StatefulWidget {
  const CanvasViewport({super.key});

  @override
  State<CanvasViewport> createState() => _CanvasViewportState();
}

class _CanvasViewportState extends State<CanvasViewport> {
  CanvasCamera _camera = CanvasCamera();
  int? _dragPointer;
  Offset? _lastDrag;
  CanvasCamera? _panZoomStart;

  String get _zoomLabel => '${(_camera.zoom * 100).round()}%';

  void _setCamera(CanvasCamera next) {
    if (next == _camera) {
      return;
    }
    setState(() => _camera = next);
  }

  void _reset() => _setCamera(_camera.reset());

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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit0): _reset,
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true): _reset,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): _reset,
        const SingleActivator(LogicalKeyboardKey.numpad0): _reset,
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
                    child: const SizedBox.expand(),
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
