import 'dart:ui';

import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/scene/scene.dart';

/// Every compatible port shows at least this much while a cable is held.
const double cablePortReadinessBase = 0.25;

/// Screen pixels over which a compatible port warms from base to full.
const double cablePortReadinessReach = 220;

/// How long compatible ports take to settle after the cable is dropped.
const Duration portReadyFade = Duration(milliseconds: 320);

String portReadinessKey(KitPortKind kind, String frameId) =>
    '${kind.name}-$frameId';

/// How strongly each compatible port should respond to the held cable, 0 to
/// 1. Incompatible ports and the source kit's own ports are absent.
Map<String, double> cablePortReadiness({
  required SceneDocument document,
  required String sourceFrameId,
  required KitPortKind sourceKind,
  required Offset cursor,
  required double zoom,
}) {
  final ports = kitPorts(document);
  final source = ports
      .where((port) => port.frameId == sourceFrameId && port.kind == sourceKind)
      .firstOrNull;
  final readiness = <String, double>{};
  for (final port in ports) {
    if (identical(port, source) ||
        !kitPortsConnect(sourceKind, port.kind) ||
        (source != null && source.peerId == port.peerId)) {
      continue;
    }
    final distance = (port.center - cursor).distance * zoom;
    final value = distance <= kitPortHitRadius * zoom
        ? 1.0
        : () {
            final near = (1 - distance / cablePortReadinessReach).clamp(
              0.0,
              1.0,
            );
            return cablePortReadinessBase +
                (1 - cablePortReadinessBase) * near * near;
          }();
    readiness[portReadinessKey(port.kind, port.frameId)] = value;
  }
  return readiness;
}
