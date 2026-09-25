import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/board_validation.dart';
import 'package:skapie/canvas/cable_activity.dart';
import 'package:skapie/canvas/cable_drag.dart';
import 'package:skapie/canvas/cable_layer.dart';
import 'package:skapie/canvas/canvas_bounds.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_grid_painter.dart';
import 'package:skapie/canvas/hit_test.dart';
import 'package:skapie/canvas/keyboard_connect.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/app/conversation_kit_viewer.dart';
import 'package:skapie/app/text_kit_editor.dart';
import 'package:skapie/app/patch_diff_viewer.dart';
import 'package:skapie/canvas/scene_object_layer.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/canvas/selection_overlay.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/cables/cable_hit.dart';
import 'package:skapie/paint/cables/cable_motion.dart';
import 'package:skapie/paint/cables/cable_painter.dart';
import 'package:skapie/paint/issue_flash_painter.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

/// Infinite canvas viewport: pan, zoom-toward-cursor, grid, origin, zoom HUD.
class CanvasViewport extends StatefulWidget {
  CanvasViewport({
    super.key,
    required this.store,
    SelectionController? selection,
    ObjectRegistry? registry,
    KitApi? kitApi,
    this.agentController,
    this.onConnect,
  }) : selection = selection ?? SelectionController(),
       kitApi =
           kitApi ??
           KitApi(store: store, registry: registry ?? createBuiltinRegistry());

  final SceneStore store;
  final SelectionController selection;
  final KitApi kitApi;
  final AgentController? agentController;

  /// Enter while a port is ringed. The host opens the connect palette.
  final VoidCallback? onConnect;
  ObjectRegistry get registry => kitApi.registry;

  @override
  State<CanvasViewport> createState() => CanvasViewportState();
}

class CanvasViewportState extends State<CanvasViewport>
    with TickerProviderStateMixin {
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
  final _cableMotion = CableMotion();
  final _activityGlow = ActivityGlow();
  final _retractions = <RetractingCable>[];
  CableHover? _cableHover;
  KitPort? _portHover;
  String? _toolHoverId;
  bool _resizeHover = false;
  bool _runHover = false;
  String? _resizeFrameId;
  double? _resizeStartHeight;
  double? _resizeStartWorldY;
  double? _resizeHeight;
  String? _cableFrameId;
  KitPortKind? _cableKind;
  Offset? _cableCursor;
  Duration? _lastTapStamp;
  String? _lastTapId;
  late final Ticker _outputTicker;
  int _seenOutputPulse = 0;
  String? _writingBodyId;
  String? _cableCycleKit;
  late final AnimationController _issueFlash;
  late final AnimationController _overview;
  late double _overviewTarget;
  late final AnimationController _portReady;
  late final AnimationController _identify;
  Set<String>? _identifyKits;
  Set<String>? _identifyCables;
  Map<String, double> _lastReadiness = const {};
  String? _inspectedIssue;
  List<({String frameId, KitPortKind kind})> _flashTargets = const [];
  bool _issuesOpen = false;
  String? _issuesForBody;
  String? _runNotice;

  Size _viewportSize = Size.zero;

  CanvasCamera get camera => _camera;

  String get _zoomLabel => '${(_camera.zoom * 100).round()}%';

  void requestBoardFocus() => _focus.requestFocus();

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
    _seenOutputPulse = widget.agentController?.outputPulse ?? 0;
    _outputTicker = createTicker((elapsed) {
      if (elapsed < outputActivityHold) {
        return;
      }
      _outputTicker.stop();
      if (!mounted) {
        return;
      }
      setState(() => _writingBodyId = null);
    });
    _issueFlash = AnimationController(
      vsync: this,
      duration: issueFlashDuration,
    );
    _overviewTarget = kitOverviewAt(_camera.zoom) ? 1.0 : 0.0;
    _overview = AnimationController(
      vsync: this,
      duration: kitOverviewTransition,
      value: _overviewTarget,
    );
    _portReady = AnimationController(vsync: this, duration: portReadyFade);
    _identify = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _identify.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _identify.addStatusListener((status) {
      if (status == AnimationStatus.dismissed &&
          widget.agentController?.trace == null &&
          mounted) {
        setState(() {
          _identifyKits = null;
          _identifyCables = null;
        });
      }
    });
    widget.store.addListener(_onStore);
    widget.selection.addListener(_onSelection);
    widget.agentController?.addListener(_onAgent);
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
    if (oldWidget.agentController != widget.agentController) {
      oldWidget.agentController?.removeListener(_onAgent);
      widget.agentController?.addListener(_onAgent);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    widget.selection.removeListener(_onSelection);
    widget.agentController?.removeListener(_onAgent);
    _inlineFocus.dispose();
    _inlineController.dispose();
    _focus.dispose();
    _cableMotion.dispose();
    _activityGlow.dispose();
    _outputTicker
      ..stop()
      ..dispose();
    _issueFlash.dispose();
    _overview.dispose();
    _portReady.dispose();
    _identify.dispose();
    super.dispose();
  }

  void _onSelection() => setState(() {});

  void _onAgent() {
    final pulse = widget.agentController?.outputPulse ?? 0;
    if (pulse != _seenOutputPulse) {
      _seenOutputPulse = pulse;
      _writingBodyId = widget.agentController?.outputBodyId;
      _outputTicker
        ..stop()
        ..start();
    }
    _syncIdentify();
    setState(() {});
  }

  void _syncIdentify() {
    final trace = widget.agentController?.trace;
    if (trace != null) {
      _identifyKits = trace.kits;
      _identifyCables = trace.cables;
      if (_identify.value < 1) {
        _identify.forward();
      }
      return;
    }
    if (_identifyKits != null && _identify.value > 0) {
      _identify.reverse();
    }
  }

  void _onStore() {
    widget.selection.syncToDocument(widget.store.document);
    final next = _clamped(_camera);
    setState(() => _camera = next);
    widget.store.noteCamera(_snapshot(next));
    _syncOverview();
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
    _syncOverview();
  }

  void _syncOverview() {
    final target = kitOverviewAt(_camera.zoom) ? 1.0 : 0.0;
    if (target == _overviewTarget) {
      return;
    }
    _overviewTarget = target;
    _overview.animateTo(target, curve: Curves.easeInOutCubic);
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
    if (_runNotice != null) {
      setState(() => _runNotice = null);
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
    final runFrame = _runButtonAt(world);
    if (runFrame != null) {
      _dragPointer = null;
      _lastDrag = null;
      _dragKind = _DragKind.none;
      _focus.requestFocus();
      widget.selection.select(runFrame.id);
      _runLlm(runFrame);
      return;
    }
    final resizeFrame = _resizeFrameAt(world);
    if (resizeFrame != null) {
      _focus.requestFocus();
      widget.selection.select(resizeFrame.id);
      _dragKind = _DragKind.resize;
      _resizeFrameId = resizeFrame.id;
      _resizeStartHeight = resizeFrame.height;
      _resizeStartWorldY = world.dy;
      _resizeHeight = resizeFrame.height;
      _cableHover = null;
      _portHover = null;
      setState(() {});
      return;
    }
    if (_scissorRect()?.contains(event.localPosition) ?? false) {
      _dragPointer = null;
      _lastDrag = null;
      _dragKind = _DragKind.none;
      _focus.requestFocus();
      _cutSelectedCable();
      return;
    }
    final port = hitKitPort(kitPorts(widget.store.document), world);
    if (port != null) {
      _focus.requestFocus();
      widget.selection.select(port.frameId);
      _dragKind = _DragKind.cable;
      _cableFrameId = port.frameId;
      _cableKind = port.kind;
      _cableCursor = world;
      _cableHover = null;
      _portReady.value = 1;
      setState(() {});
      return;
    }
    final cableHit = _cableAt(event.localPosition);
    if (cableHit != null) {
      _dragPointer = null;
      _lastDrag = null;
      _dragKind = _DragKind.none;
      _focus.requestFocus();
      widget.selection.selectCable(cableHit.cable.id);
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
      setState(() => _inspectedIssue = null);
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
      final frame = kitFrameForSelection(
        document: widget.store.document,
        selectedId: hit.id,
      );
      if (frame != null && kitIdOf(frame) == codingPatchProposalKitId) {
        final body = patchProposalBody(widget.store.document, frame.id);
        final diff = body?.props['diff']?.toString() ?? '';
        if (diff.isNotEmpty) {
          widget.selection.cancelMove();
          _dragKind = _DragKind.none;
          showPatchDiffViewer(
            context: context,
            path: body!.props['path']?.toString() ?? '',
            diff: diff,
            proposalId: body.props[proposalIdProp]?.toString() ?? '',
          );
          return;
        }
      }
      final previewBody = _previewKitBody(hit);
      if (previewBody != null) {
        widget.selection.cancelMove();
        _dragKind = _DragKind.none;
        _openPreviewKit(previewBody);
        return;
      }
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

  void _onHover(PointerHoverEvent event) {
    if (_dragKind != _DragKind.none) {
      if (_cableHover != null ||
          _portHover != null ||
          _toolHoverId != null ||
          _resizeHover ||
          _runHover) {
        setState(() {
          _cableHover = null;
          _portHover = null;
          _toolHoverId = null;
          _resizeHover = false;
          _runHover = false;
        });
      }
      return;
    }
    if (_scissorRect()?.contains(event.localPosition) ?? false) {
      return;
    }
    final world = screenToWorld(event.localPosition, _viewportSize, _camera);
    final runHover = _runButtonAt(world) != null;
    final resize = runHover ? null : _resizeFrameAt(world);
    final port = resize == null
        ? hitKitPort(kitPorts(widget.store.document), world)
        : null;
    final toolId = _toolFrameAt(world)?.id;
    final next = port == null && resize == null
        ? _cableAt(event.localPosition)
        : null;
    final same =
        _portHover?.frameId == port?.frameId &&
        _portHover?.kind == port?.kind &&
        _cableHover?.cable.id == next?.cable.id &&
        _cableHover?.screen == next?.screen &&
        _toolHoverId == toolId &&
        _resizeHover == (resize != null) &&
        _runHover == runHover;
    if (same) {
      return;
    }
    setState(() {
      _portHover = port;
      _cableHover = next;
      _toolHoverId = toolId;
      _resizeHover = resize != null;
      _runHover = runHover;
    });
  }

  SceneObject? _runButtonAt(Offset world) {
    if (kitOverviewAt(_camera.zoom)) {
      return null;
    }
    for (final object in widget.store.document.objects) {
      if (!isLlmKitObject(object) || object.props[skapieRoleProp] != 'frame') {
        continue;
      }
      if (llmRunButtonContains(object, world)) {
        return object;
      }
    }
    return null;
  }

  void _runLlm(SceneObject frame) {
    final controller = widget.agentController;
    if (controller == null) {
      return;
    }
    final body = llmKitBodyForSelection(
      document: widget.store.document,
      selectedId: frame.id,
    );
    if (controller.runningBodyId != null) {
      if (body != null && controller.runningBodyId == body.id) {
        controller.interruptRun();
      }
      return;
    }
    if (body == null) {
      return;
    }
    final blockers = validateBoard(widget.store.document).runBlockers(body.id);
    if (blockers.isNotEmpty) {
      setState(() {
        _runNotice =
            "Can't run ${kitDisplayName(widget.store.document, frame)}: "
            '${blockers.first.message}';
        _issuesForBody = body.id;
        _issuesOpen = true;
      });
      _inspectIssue(blockers.first, select: false);
      return;
    }
    final prompt = llmCableInput(widget.store.document, body.id).trim();
    controller.sendUser(prompt, targetBodyId: body.id).catchError((_) {});
  }

  SceneObject? _resizeFrameAt(Offset world) {
    if (kitOverviewAt(_camera.zoom)) {
      return null;
    }
    for (final object in widget.store.document.objects) {
      if (!isLlmKitObject(object) || object.props[skapieRoleProp] != 'frame') {
        continue;
      }
      final height = object.id == _resizeFrameId && _resizeHeight != null
          ? _resizeHeight!
          : object.height;
      final shown = object.copyWith(height: height);
      if (llmResizeHandleContains(shown, world)) {
        return object;
      }
    }
    return null;
  }

  SceneObject? _toolFrameAt(Offset world) {
    final hit = hitTestObjects(widget.store.document.objects, world);
    if (hit == null) {
      return null;
    }
    final frame =
        kitFrameForSelection(
          document: widget.store.document,
          selectedId: hit.id,
        ) ??
        hit;
    final kitId = kitIdOf(frame) ?? '';
    if (!kitId.startsWith('tools.')) {
      return null;
    }
    return frame;
  }

  CableHover? _cableAt(Offset local) {
    if (_viewportSize.isEmpty || _dragKind != _DragKind.none) {
      return null;
    }
    final world = screenToWorld(local, _viewportSize, _camera);
    if (hitTestObjects(widget.store.document.objects, world) != null) {
      return null;
    }
    return hitCable(
      cables: _allCables(),
      screenPoint: local,
      worldEnds: (cable) => (
        from: _shownWorld(cable.from, cable.sourceId),
        to: _shownWorld(cable.to, cable.targetFrameId),
      ),
      toScreen: (point) => worldToScreen(point, _viewportSize, _camera),
      zoom: _camera.zoom,
    );
  }

  Offset _shownWorld(Offset center, String id) {
    if (_previewIds.contains(id)) {
      return center + widget.selection.previewDelta;
    }
    return center;
  }

  List<SceneCable> _allCables() => [
    ...sceneCables(widget.store.document),
    ...validateBoard(widget.store.document).extraCables,
  ];

  SceneCable? get _selectedCable {
    final id = widget.selection.selectedCableId;
    if (id == null) {
      return null;
    }
    for (final cable in _allCables()) {
      if (cable.id == id) {
        return cable;
      }
    }
    return null;
  }

  /// Cut the selected cable from its middle. Used by Delete and the badge.
  void _cutSelectedCable() {
    final cable = _selectedCable;
    if (cable == null) {
      return;
    }
    retractCable(cable);
  }

  /// Remove [cable] and play the same end-retraction as a scissor cut.
  void retractCable(SceneCable cable) {
    setState(() {
      _retractions.add(
        RetractingCable(
          from: _shownWorld(cable.from, cable.sourceId),
          to: _shownWorld(cable.to, cable.targetFrameId),
          cut: 0.5,
          color: cable.color,
        ),
      );
      _cableHover = null;
    });
    if (widget.selection.selectedCableId == cable.id) {
      widget.selection.selectCable(null);
    }
    disconnectSceneCable(kitApi: widget.kitApi, cable: cable);
  }

  void _cycleKit(int step) {
    final id = cycleKitFrameId(
      document: widget.store.document,
      selectedId: widget.selection.selectedId,
      step: step,
    );
    if (id == null) {
      return;
    }
    widget.selection.select(id);
  }

  /// P and Shift-P. With no kit selected, the keys do nothing.
  void _cyclePort(int step) {
    final selected = widget.selection.selectedId;
    if (selected == null) {
      return;
    }
    final frame = kitFrameForSelection(
      document: widget.store.document,
      selectedId: selected,
    );
    if (frame == null) {
      return;
    }
    final ports = [
      for (final port in kitPorts(widget.store.document))
        if (port.frameId == frame.id) port,
    ];
    final kind = cyclePortKind(
      ports: ports,
      current: widget.selection.selectedPort,
      step: step,
    );
    if (kind == null) {
      return;
    }
    widget.selection.selectPort(kind);
  }

  /// Enter with a kit but no port ringed does nothing.
  void _connectFromKeyboard() {
    if (widget.selection.selectedId == null ||
        widget.selection.selectedPort == null) {
      return;
    }
    widget.onConnect?.call();
  }

  /// Step through cables: those of the selected kit, else every cable.
  void _cycleCable(int step) {
    final selectedKit = widget.selection.selectedId;
    if (selectedKit != null) {
      _cableCycleKit =
          kitFrameForSelection(
            document: widget.store.document,
            selectedId: selectedKit,
          )?.id ??
          selectedKit;
    } else if (widget.selection.selectedCableId == null) {
      _cableCycleKit = null;
    }
    final kit = _cableCycleKit;
    final cables = [
      for (final cable in _allCables())
        if (kit == null || cable.sourceId == kit || cable.targetFrameId == kit)
          cable,
    ]..sort((a, b) => a.id.compareTo(b.id));
    if (cables.isEmpty) {
      return;
    }
    final current = cables.indexWhere(
      (cable) => cable.id == widget.selection.selectedCableId,
    );
    final next = current < 0
        ? (step > 0 ? 0 : cables.length - 1)
        : (current + step) % cables.length;
    widget.selection.selectCable(cables[next].id);
  }

  Offset? _cableMidScreen(SceneCable cable) {
    final from = worldToScreen(
      _shownWorld(cable.from, cable.sourceId),
      _viewportSize,
      _camera,
    );
    final to = worldToScreen(
      _shownWorld(cable.to, cable.targetFrameId),
      _viewportSize,
      _camera,
    );
    final metrics = cableCurve(from, to, _camera.zoom).computeMetrics();
    for (final metric in metrics) {
      return metric.getTangentForOffset(metric.length / 2)?.position;
    }
    return null;
  }

  /// Live while a cable is held; the last map lingers while it fades out.
  Map<String, double> _heldPortReadiness() {
    final frameId = _cableFrameId;
    final kind = _cableKind;
    final cursor = _cableCursor;
    if (frameId != null && kind != null && cursor != null) {
      _lastReadiness = cablePortReadiness(
        document: widget.store.document,
        sourceFrameId: frameId,
        sourceKind: kind,
        cursor: cursor,
        zoom: _camera.zoom,
      );
    }
    return _lastReadiness;
  }

  /// Scissors appear only on a selected cable, at its middle.
  Rect? _scissorRect() {
    if (_viewportSize.isEmpty) {
      return null;
    }
    final selected = _selectedCable;
    final anchor = selected == null ? null : _cableMidScreen(selected);
    if (anchor == null) {
      return null;
    }
    return Rect.fromCenter(center: anchor, width: 22, height: 22);
  }

  /// An unconnected drop pulls the cable back into its source port.
  void _retreatCable(String frameId, KitPortKind kind, Offset world) {
    final document = widget.store.document;
    final source = kitPorts(document)
        .where((port) => port.frameId == frameId && port.kind == kind)
        .firstOrNull;
    if (source == null || (source.center - world).distance < 4) {
      return;
    }
    final refused = cableDragRefusal(document, frameId, kind, world);
    final frame = document.objectById(frameId);
    final exits = kitPortIsOutput(kind);
    setState(() {
      _retractions.add(
        RetractingCable(
          from: _shownWorld(source.center, frameId),
          to: refused?.port.center ?? world,
          cut: 1,
          color: refused != null
              ? PaintScope.of(context).danger
              : frame == null
              ? PaintScope.of(context).accent
              : kitAccentColor(frame),
          exitsRight: exits,
          entersFromLeft: refused == null
              ? exits
              : !kitPortIsOutput(refused.port.kind),
        ),
      );
    });
  }

  void _endRetraction(RetractingCable cable) {
    if (!_retractions.contains(cable)) {
      return;
    }
    setState(() => _retractions.remove(cable));
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
      return;
    }
    if (_dragKind == _DragKind.resize &&
        _resizeStartHeight != null &&
        _resizeStartWorldY != null) {
      final world = screenToWorld(event.localPosition, _viewportSize, _camera);
      final next = (_resizeStartHeight! + (world.dy - _resizeStartWorldY!))
          .clamp(llmFrameHeight, 720.0);
      setState(() => _resizeHeight = next);
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
    final cableCursor = _cableCursor;
    final resizeId = _resizeFrameId;
    final resizeHeight = _resizeHeight;
    _dragPointer = null;
    _lastDrag = null;
    _moveWorldStart = null;
    _dragKind = _DragKind.none;
    _cableFrameId = null;
    _cableKind = null;
    _cableCursor = null;
    _resizeFrameId = null;
    _resizeStartHeight = null;
    _resizeStartWorldY = null;
    _resizeHeight = null;
    if (kind == _DragKind.resize) {
      if (commitMove && resizeId != null && resizeHeight != null) {
        _commitResize(resizeId, resizeHeight);
      }
      setState(() {});
      return;
    }
    if (kind == _DragKind.cable) {
      var connected = false;
      if (commitMove &&
          upLocal != null &&
          cableFrame != null &&
          cableKind != null) {
        connected = _completeCable(cableFrame, cableKind, upLocal);
      }
      final end = upLocal == null
          ? cableCursor
          : screenToWorld(upLocal, _viewportSize, _camera);
      if (!connected &&
          cableFrame != null &&
          cableKind != null &&
          end != null) {
        _retreatCable(cableFrame, cableKind, end);
      }
      _portReady.animateTo(
        0,
        duration: portReadyFade,
        curve: Curves.easeOutCubic,
      );
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

  Widget? _toolDescription(Size viewportSize) {
    final frame = widget.store.document.objectById(_toolHoverId ?? '');
    final text = frame?.props['description']?.toString().trim() ?? '';
    if (frame == null || text.isEmpty) {
      return null;
    }
    final tokens = PaintScope.of(context);
    final origin = worldToScreen(
      Offset(frame.x, frame.y + frame.height),
      viewportSize,
      _camera,
    );
    return Positioned(
      left: origin.dx,
      top: origin.dy + 8,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                text,
                key: const Key('tool-hover-description'),
                style: TextStyle(color: tokens.ink, fontSize: 12, height: 1.3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _commitResize(String frameId, double height) {
    final frame = widget.store.document.objectById(frameId);
    if (frame == null) {
      return;
    }
    final body = llmKitBodyForSelection(
      document: widget.store.document,
      selectedId: frameId,
    );
    final bodyHeight = height - 24;
    if (body != null && height < frame.height) {
      widget.kitApi.updateFrame(id: body.id, height: bodyHeight);
    }
    widget.kitApi.updateFrame(id: frame.id, height: height);
    if (body != null && height >= frame.height) {
      widget.kitApi.updateFrame(id: body.id, height: bodyHeight);
    }
  }

  /// True when the drop made a connection.
  bool _completeCable(String frameId, KitPortKind sourceKind, Offset upLocal) {
    final ports = kitPorts(widget.store.document);
    final world = screenToWorld(upLocal, _viewportSize, _camera);
    final target = hitKitPort(ports, world);
    final source = ports
        .where((port) => port.frameId == frameId && port.kind == sourceKind)
        .firstOrNull;
    final refused = cableDragRefusal(
      widget.store.document,
      frameId,
      sourceKind,
      world,
    );
    if (refused != null) {
      setState(() => _runNotice = 'Not connected: ${refused.reason}');
      return false;
    }
    if (source == null ||
        target == null ||
        !kitPortsConnect(sourceKind, target.kind)) {
      return false;
    }
    connectKitPorts(kitApi: widget.kitApi, from: source, to: target);
    return true;
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
    setState(() => _inspectedIssue = null);
    widget.selection.select(null);
  }

  void _deleteSelected() {
    if (widget.selection.isMoving) {
      return;
    }
    if (widget.selection.selectedCableId != null) {
      _cutSelectedCable();
      return;
    }
    final id = widget.selection.selectedId;
    if (id == null) {
      return;
    }
    removeKitSelection(kitApi: widget.kitApi, selectedId: id);
    widget.selection.syncToDocument(widget.store.document);
  }

  SceneObject? _previewKitBody(SceneObject hit) {
    final kitId = kitIdOf(hit);
    if (kitId == codingPatchProposalKitId ||
        kitId == codingReviewDecisionKitId ||
        kitId == codingApplyPatchKitId ||
        kitId == codingWriteScopeKitId ||
        kitId == codingCheckSpecKitId ||
        kitId == codingRunCheckKitId ||
        kitId == codingCheckResultKitId) {
      return null;
    }
    if (!kitUsesTextPreview(kitId)) {
      return null;
    }
    if (hit.props[skapieRoleProp] == 'body') {
      return hit;
    }
    if (hit.props[skapieRoleProp] != 'frame') {
      return null;
    }
    return kitId == harnessConversationKitId
        ? conversationBody(widget.store.document, hit)
        : textKitBody(widget.store.document, hit);
  }

  void _openPreviewKit(SceneObject body) {
    final frame = kitFrameForSelection(
      document: widget.store.document,
      selectedId: body.id,
    );
    if (kitIdOf(body) == harnessConversationKitId) {
      showConversationKitViewer(
        context: context,
        kitApi: widget.kitApi,
        bodyId: body.id,
        title: frame == null
            ? 'Conversation'
            : kitDisplayName(widget.store.document, frame),
      );
      return;
    }
    showTextKitEditor(
      context: context,
      kitApi: widget.kitApi,
      bodyId: body.id,
      title: frame == null
          ? 'Text'
          : kitDisplayName(widget.store.document, frame),
      content: body.props['content']?.toString() ?? '',
    );
  }

  bool _canInlineEdit(SceneObject object) {
    if (object.type != textTypeId) {
      return false;
    }
    final kitId = kitIdOf(object);
    if (kitId == codingPatchProposalKitId ||
        kitId == codingReviewDecisionKitId ||
        kitId == codingApplyPatchKitId ||
        kitId == codingWriteScopeKitId ||
        kitId == codingCheckSpecKitId ||
        kitId == codingRunCheckKitId ||
        kitId == codingCheckResultKitId) {
      return false;
    }
    if (isLlmKitObject(object) || kitUsesTextPreview(kitIdOf(object))) {
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
        final tokens = PaintScope.of(context);
        final validation = validateBoard(
          widget.store.document,
          resizeFrameId: _resizeFrameId,
          resizeHeight: _resizeHeight,
        );
        final scissors = _scissorRect();
        final selectedCable = widget.selection.selectedCableId;
        if (selectedCable != null && _selectedCable == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                widget.selection.selectedCableId == selectedCable &&
                _selectedCable == null) {
              widget.selection.selectCable(null);
            }
          });
        }
        final controller = widget.agentController;
        final activity = CableActivity(
          runningBodyId: controller?.runningBodyId,
          seedPorts: controller?.seedPorts ?? const {},
          activeToolFrameId: controller?.activeToolFrameId,
          toolPulse: controller?.toolPulse ?? 0,
          toolPulseFrameId: controller?.toolPulseFrameId,
          toolPulseBodyId: controller?.toolPulseBodyId,
          toolResultPulse: controller?.toolResultPulse ?? 0,
          toolResultFrameId: controller?.toolResultFrameId,
          toolResultBodyId: controller?.toolResultBodyId,
          writingBodyId: _writingBodyId,
        );
        if (size != _viewportSize) {
          _viewportSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _setCamera(_camera);
            }
          });
        }

        final board = CallbackShortcuts(
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
            const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
                _cycleCable(1),
            const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
                _cycleCable(-1),
            const SingleActivator(LogicalKeyboardKey.tab): () => _cycleKit(1),
            const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
                _cycleKit(-1),
            const SingleActivator(LogicalKeyboardKey.keyP): () => _cyclePort(1),
            const SingleActivator(LogicalKeyboardKey.keyP, shift: true): () =>
                _cyclePort(-1),
            const SingleActivator(LogicalKeyboardKey.enter):
                _connectFromKeyboard,
            const SingleActivator(LogicalKeyboardKey.numpadEnter):
                _connectFromKeyboard,
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
                cursor: _dragKind == _DragKind.cable
                    ? SystemMouseCursors.grabbing
                    : _dragKind == _DragKind.resize || _resizeHover
                    ? SystemMouseCursors.resizeUpDown
                    : _runHover
                    ? SystemMouseCursors.click
                    : _portHover != null
                    ? SystemMouseCursors.precise
                    : _cableHover != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.grab,
                onHover: _onHover,
                onExit: (_) {
                  if (_cableHover != null ||
                      _portHover != null ||
                      _toolHoverId != null ||
                      _resizeHover ||
                      _runHover) {
                    setState(() {
                      _cableHover = null;
                      _portHover = null;
                      _toolHoverId = null;
                      _resizeHover = false;
                      _runHover = false;
                    });
                  }
                },
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
                      dragFrameId: _cableFrameId,
                      dragKind: _cableKind,
                      dragCursor: _cableCursor,
                      resizeFrameId: _resizeFrameId,
                      resizeHeight: _resizeHeight,
                      paintDrag: false,
                      activity: activity,
                      glow: _activityGlow,
                      motion: _cableMotion,
                      retractions: _retractions,
                      onRetractionDone: _endRetraction,
                      validation: validation,
                      invalidColor: tokens.danger,
                      selectedCableId: widget.selection.selectedCableId,
                      traceCables: _identifyCables ?? const {},
                      traceKits: _identifyKits ?? const {},
                      traceAmount: Curves.easeInOut.transform(_identify.value),
                    ),
                    AnimatedBuilder(
                      animation: Listenable.merge([_overview, _portReady]),
                      builder: (context, _) => SceneObjectLayer(
                        camera: _camera,
                        viewportSize: size,
                        objects: objects,
                        registry: widget.registry,
                        selectedId: widget.selection.selectedId,
                        focusedPort: widget.selection.selectedPort,
                        previewDelta: widget.selection.previewDelta,
                        previewIds: _previewIds,
                        activity: activity,
                        glow: _activityGlow,
                        resizeFrameId: _resizeFrameId,
                        resizeHeight: _resizeHeight,
                        blockedRunBodyIds: blockedLlmBodies(validation),
                        identifiedKits: _identifyKits,
                        identifyAmount: Curves.easeInOut.transform(
                          _identify.value,
                        ),
                        overviewProgress: _overview.value,
                        portReadiness: {
                          for (final entry in _heldPortReadiness().entries)
                            entry.key: entry.value * _portReady.value,
                        },
                      ),
                    ),
                    ?_toolDescription(size),
                    if (_cableFrameId != null && _cableCursor != null)
                      CableLayer(
                        camera: _camera,
                        viewportSize: size,
                        document: widget.store.document,
                        dragFrameId: _cableFrameId,
                        dragKind: _cableKind,
                        dragCursor: _cableCursor,
                        previewOnly: true,
                        invalidColor: tokens.danger,
                      ),
                    ?_cableRefusalLabel(size, tokens),
                    ?_issueFlashLayer(size, tokens),
                    if (_selectedObject != null &&
                        !isKitObject(_selectedObject!))
                      SceneSelectionOverlay(
                        camera: _camera,
                        viewportSize: size,
                        object: _selectedObject!,
                        previewDelta: widget.selection.previewDelta,
                      ),
                    ?_inlineEditor(size),
                    if (scissors != null)
                      Positioned.fromRect(
                        rect: scissors,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const Key('cable-cut'),
                            decoration: BoxDecoration(
                              color:
                                  (_cableHover?.cable ?? _selectedCable)
                                      ?.color ??
                                  tokens.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(
                              width: 22,
                              height: 22,
                              child: Icon(
                                Icons.content_cut,
                                size: 14,
                                color: Color(0xFFFFF8EC),
                              ),
                            ),
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
        final issues = _boardIssues(validation, tokens);
        return Stack(
          fit: StackFit.expand,
          children: [
            board,
            if (issues != null) Positioned(left: 12, top: 12, child: issues),
          ],
        );
      },
    );
  }

  Widget? _cableRefusalLabel(Size viewportSize, PaintTokens tokens) {
    final frameId = _cableFrameId;
    final kind = _cableKind;
    final cursor = _cableCursor;
    if (frameId == null || kind == null || cursor == null) {
      return null;
    }
    final refused = cableDragRefusal(
      widget.store.document,
      frameId,
      kind,
      cursor,
    );
    if (refused == null) {
      return null;
    }
    final at = worldToScreen(cursor, viewportSize, _camera);
    return Positioned(
      left: at.dx + 14,
      top: at.dy + 14,
      child: IgnorePointer(
        child: _notice(tokens, refused.reason, key: const Key('cable-refusal')),
      ),
    );
  }

  Widget _notice(PaintTokens tokens, String text, {Key? key}) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: tokens.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.danger.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(text, style: TextStyle(color: tokens.ink, fontSize: 12)),
      ),
    );
  }

  /// Board-level list of issues. Run failures open it scoped to that LLM.
  Widget? _boardIssues(BoardValidation validation, PaintTokens tokens) {
    final all = validation.issues;
    final focus = _issuesForBody;
    final shown = focus == null ? all : validation.runBlockers(focus);
    final notice = _runNotice;
    if (all.isEmpty && notice == null) {
      return null;
    }
    final errors = all
        .where((issue) => issue.severity == BoardIssueSeverity.error)
        .length;
    final label = all.isEmpty
        ? 'Board OK'
        : errors > 0
        ? '$errors ${errors == 1 ? 'issue blocks' : 'issues block'} Run'
        : '${all.length} ${all.length == 1 ? 'warning' : 'warnings'}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notice != null) ...[
              _notice(tokens, notice, key: const Key('board-run-notice')),
              const SizedBox(height: 6),
            ],
            if (all.isNotEmpty)
              InkWell(
                key: const Key('board-issues-button'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  _issuesOpen = !_issuesOpen || _issuesForBody != null;
                  _issuesForBody = null;
                }),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.panel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: errors > 0 ? tokens.danger : tokens.hairline,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 14,
                          color: errors > 0 ? tokens.danger : tokens.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(color: tokens.ink, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_issuesOpen && shown.isNotEmpty) ...[
              const SizedBox(height: 6),
              DecoratedBox(
                key: const Key('board-issues-panel'),
                decoration: BoxDecoration(
                  color: tokens.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tokens.hairline),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, issue) in shown.indexed)
                        _issueRow(issue, tokens, index),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Tint the row, select its kit, bring its ports on screen, and flash them.
  void _inspectIssue(BoardIssue issue, {bool select = true}) {
    final document = widget.store.document;
    final ports = boardIssuePorts(document, issue);
    setState(() {
      _inspectedIssue = boardIssueKey(issue);
      _flashTargets = [
        for (final port in ports) (frameId: port.frameId, kind: port.kind),
      ];
    });
    if (select && document.objectById(issue.frameId) != null) {
      widget.selection.select(issue.frameId);
    }
    if (ports.isNotEmpty) {
      _reveal(ports.first.center);
    }
    _issueFlash.forward(from: 0);
  }

  void _reveal(Offset world) {
    if (_viewportSize.isEmpty) {
      return;
    }
    final screen = worldToScreen(world, _viewportSize, _camera);
    final safe = (Offset.zero & _viewportSize).deflate(64);
    if (safe.contains(screen)) {
      return;
    }
    _setCamera(CanvasCamera(offset: world, zoom: _camera.zoom));
  }

  Widget? _issueFlashLayer(Size size, PaintTokens tokens) {
    if (_flashTargets.isEmpty) {
      return null;
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _issueFlash,
          builder: (context, _) {
            if (!_issueFlash.isAnimating) {
              return const SizedBox.shrink();
            }
            final ports = kitPorts(widget.store.document);
            final points = [
              for (final target in _flashTargets)
                for (final port in ports)
                  if (port.frameId == target.frameId &&
                      port.kind == target.kind)
                    worldToScreen(
                      _shownWorld(port.center, port.frameId),
                      size,
                      _camera,
                    ),
            ];
            return CustomPaint(
              key: const Key('issue-port-flash'),
              painter: IssueFlashPainter(
                points: points,
                t: _issueFlash.value,
                color: tokens.danger,
                zoom: _camera.zoom,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }

  Widget _issueRow(BoardIssue issue, PaintTokens tokens, int index) {
    final frame = widget.store.document.objectById(issue.frameId);
    final kit = frame == null
        ? ''
        : kitDisplayName(widget.store.document, frame);
    final error = issue.severity == BoardIssueSeverity.error;
    final inspected = boardIssueKey(issue) == _inspectedIssue;
    return Material(
      key: ValueKey('board-issue-row-$index'),
      color: inspected
          ? tokens.accent.withValues(alpha: 0.16)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _inspectIssue(issue),
        hoverColor: tokens.ink.withValues(alpha: 0.07),
        highlightColor: tokens.accent.withValues(alpha: 0.12),
        splashColor: tokens.accent.withValues(alpha: 0.12),
        mouseCursor: SystemMouseCursors.click,
        child: _issueRowContent(issue, tokens, kit, error),
      ),
    );
  }

  Widget _issueRowContent(
    BoardIssue issue,
    PaintTokens tokens,
    String kit,
    bool error,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              error ? Icons.block : Icons.warning_amber,
              size: 13,
              color: error ? tokens.danger : tokens.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: issue.message),
                  if (kit.isNotEmpty)
                    TextSpan(
                      text: '  $kit',
                      style: TextStyle(color: tokens.muted),
                    ),
                ],
              ),
              style: TextStyle(color: tokens.ink, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DragKind { none, pan, move, cable, resize }
