import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

class CableLayer extends StatelessWidget {
  const CableLayer({
    super.key,
    required this.camera,
    required this.viewportSize,
    required this.document,
    this.previewDelta = Offset.zero,
    this.previewIds = const {},
    this.dragFrameId,
    this.dragKind,
    this.dragCursor,
    this.previewOnly = false,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final SceneDocument document;
  final Offset previewDelta;
  final Set<String> previewIds;
  final String? dragFrameId;
  final KitPortKind? dragKind;
  final Offset? dragCursor;
  final bool previewOnly;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CablePainter(
          camera: camera,
          viewportSize: viewportSize,
          cables: _cables(),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  List<_Cable> _cables() {
    final cables = <_Cable>[];
    if (!previewOnly) {
      for (final frame in textFrames(document)) {
        final llmId = textConnectedLlmId(frame);
        final llm = llmId.isEmpty ? null : _llmFrameForBody(llmId);
        if (llm == null) {
          continue;
        }
        final to = textConnectedPort(frame) == llmContextPort
            ? llmContextCenter(llm)
            : llmInputCenter(llm);
        cables.add(
          _Cable(
            from: _shown(textOutputCenter(frame), frame.id),
            to: _shown(to, llm.id),
            color: kitAccentColor(llm),
          ),
        );
      }
      for (final frame in toolFrames(document)) {
        final llmId = frame.props[attachedToProp]?.toString().trim() ?? '';
        final llm = llmId.isEmpty ? null : _llmFrameForBody(llmId);
        if (llm == null) {
          continue;
        }
        cables.add(
          _Cable(
            from: _shown(toolOutputCenter(frame), frame.id),
            to: _shown(llmToolsCenter(llm), llm.id),
            color: kitAccentColor(llm),
          ),
        );
      }
      for (final body in llmBodies(document)) {
        final targetId = body.props[outputToProp]?.toString().trim() ?? '';
        final source = _llmFrameForBody(body.id);
        final target = targetId.isEmpty ? null : _llmFrameForBody(targetId);
        if (source == null || target == null) {
          continue;
        }
        final to =
            (body.props[outputPortProp]?.toString().trim() ?? '') ==
                llmContextPort
            ? llmContextCenter(target)
            : llmInputCenter(target);
        cables.add(
          _Cable(
            from: _shown(llmOutputCenter(source), source.id),
            to: _shown(to, target.id),
            color: kitAccentColor(target),
          ),
        );
      }
    }
    final dragId = dragFrameId;
    final cursor = dragCursor;
    final kind = dragKind;
    if (dragId != null && cursor != null && kind != null) {
      final frame = document.objectById(dragId);
      if (frame != null) {
        final snapped = _snap(kind, cursor, frame);
        final target = snapped == null
            ? null
            : document.objectById(snapped.frameId);
        cables.add(
          _Cable(
            from: _shown(_center(frame, kind), frame.id),
            to: snapped?.center ?? cursor,
            color: target == null
                ? kitAccentColor(frame)
                : kitAccentColor(target),
            preview: true,
          ),
        );
      }
    }
    return cables;
  }

  KitPort? _snap(KitPortKind sourceKind, Offset cursor, SceneObject source) {
    final hit = hitKitPort(kitPorts(document), cursor);
    if (hit == null || !kitPortAccepts(sourceKind, hit.kind)) {
      return null;
    }
    if (sourceKind == KitPortKind.llmOutput) {
      final sourcePort = kitPorts(document)
          .where(
            (port) =>
                port.frameId == source.id && port.kind == KitPortKind.llmOutput,
          )
          .firstOrNull;
      if (sourcePort != null && sourcePort.peerId == hit.peerId) {
        return null;
      }
    }
    return hit;
  }

  Offset _center(SceneObject frame, KitPortKind kind) {
    return switch (kind) {
      KitPortKind.textOut => textOutputCenter(frame),
      KitPortKind.toolOut => toolOutputCenter(frame),
      KitPortKind.llmInput => llmInputCenter(frame),
      KitPortKind.llmContext => llmContextCenter(frame),
      KitPortKind.llmTools => llmToolsCenter(frame),
      KitPortKind.llmOutput => llmOutputCenter(frame),
    };
  }

  Offset _shown(Offset center, String id) {
    if (previewIds.contains(id)) {
      return center + previewDelta;
    }
    return center;
  }

  SceneObject? _llmFrameForBody(String bodyId) {
    return kitFrameForSelection(document: document, selectedId: bodyId);
  }
}

class _Cable {
  const _Cable({
    required this.from,
    required this.to,
    required this.color,
    this.preview = false,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final bool preview;
}

class _CablePainter extends CustomPainter {
  const _CablePainter({
    required this.camera,
    required this.viewportSize,
    required this.cables,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final List<_Cable> cables;

  @override
  void paint(Canvas canvas, Size size) {
    for (final cable in cables) {
      final start = worldToScreen(cable.from, viewportSize, camera);
      final end = worldToScreen(cable.to, viewportSize, camera);
      final path = _curve(start, end, camera.zoom);
      final glow = Paint()
        ..color = cable.color.withValues(alpha: cable.preview ? 0.22 : 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5 * camera.zoom
        ..strokeCap = StrokeCap.round
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 4 * camera.zoom);
      canvas.drawPath(path, glow);
      final core = Paint()
        ..color = cable.color.withValues(alpha: cable.preview ? 0.9 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35 * camera.zoom
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, core);
    }
  }

  Path _curve(Offset start, Offset end, double zoom) {
    final span = (end.dx - start.dx).abs();
    final bend = (span * 0.45).clamp(28.0 * zoom, 160.0 * zoom);
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + bend,
        start.dy,
        end.dx - bend,
        end.dy,
        end.dx,
        end.dy,
      );
  }

  @override
  bool shouldRepaint(covariant _CablePainter oldDelegate) {
    if (oldDelegate.camera != camera ||
        oldDelegate.viewportSize != viewportSize ||
        oldDelegate.cables.length != cables.length) {
      return true;
    }
    for (var i = 0; i < cables.length; i++) {
      final previous = oldDelegate.cables[i];
      final next = cables[i];
      if (previous.from != next.from ||
          previous.to != next.to ||
          previous.color != next.color ||
          previous.preview != next.preview) {
        return true;
      }
    }
    return false;
  }
}
