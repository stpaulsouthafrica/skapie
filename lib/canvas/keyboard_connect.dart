import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

/// Next kit frame in reading order. [step] is 1 for Tab and -1 for Shift-Tab.
///
/// Frames are ordered top to bottom, then left to right. A selection that is
/// not a kit frame starts at the first or last frame.
String? cycleKitFrameId({
  required SceneDocument document,
  required String? selectedId,
  required int step,
}) {
  final frames =
      [
        for (final object in document.objects)
          if (object.props[skapieRoleProp] == 'frame' && isKitObject(object))
            object,
      ]..sort((a, b) {
        final down = a.y.compareTo(b.y);
        if (down != 0) {
          return down;
        }
        final across = a.x.compareTo(b.x);
        if (across != 0) {
          return across;
        }
        return a.id.compareTo(b.id);
      });
  if (frames.isEmpty) {
    return null;
  }
  final current = kitFrameForSelection(
    document: document,
    selectedId: selectedId,
  );
  final index = current == null
      ? -1
      : frames.indexWhere((frame) => frame.id == current.id);
  if (index < 0) {
    return step < 0 ? frames.last.id : frames.first.id;
  }
  return frames[_wrap(index + step, frames.length)].id;
}

/// Next port on a kit, in the order [kitPorts] draws them.
///
/// With no current port, a positive step rings the first port and a negative
/// step rings the last.
KitPortKind? cyclePortKind({
  required List<KitPort> ports,
  required KitPortKind? current,
  required int step,
}) {
  if (ports.isEmpty) {
    return null;
  }
  final index = current == null
      ? -1
      : ports.indexWhere((port) => port.kind == current);
  if (index < 0) {
    return step < 0 ? ports.last.kind : ports.first.kind;
  }
  return ports[_wrap(index + step, ports.length)].kind;
}

/// One compatible port the keyboard can cable to [source].
class ConnectChoice {
  const ConnectChoice({required this.port, required this.label});

  final KitPort port;
  final String label;
}

/// Targets a drag from [source] could land on, minus the pair already cabled.
///
/// Other free ports on a multi-input stay. Incompatible ports are absent.
List<ConnectChoice> connectChoices({
  required SceneDocument document,
  required KitPort source,
}) {
  final cables = sceneCables(document);
  final choices = <ConnectChoice>[];
  for (final port in kitPorts(document)) {
    if (port.peerId == source.peerId) {
      continue;
    }
    if (!kitPortsConnect(source.kind, port.kind)) {
      continue;
    }
    if (cables.any((cable) => _samePair(cable, source, port))) {
      continue;
    }
    final frame = document.objectById(port.frameId);
    if (frame == null) {
      continue;
    }
    choices.add(
      ConnectChoice(
        port: port,
        label:
            '${kitDisplayName(document, frame)} · ${kitPortSpecOf(port.kind).label}',
      ),
    );
  }
  final counts = <String, int>{};
  for (final choice in choices) {
    counts[choice.label] = (counts[choice.label] ?? 0) + 1;
  }
  return [
    for (final choice in choices)
      if ((counts[choice.label] ?? 0) > 1)
        ConnectChoice(
          port: choice.port,
          label: '${choice.label} · ${choice.port.frameId}',
        )
      else
        choice,
  ];
}

/// A cable already attached to the port Connect mode was opened from.
class PortConnection {
  const PortConnection({required this.cable, required this.label});

  final SceneCable cable;
  final String label;
}

/// Cables on [source], labeled from the other end, ready to cut.
List<PortConnection> portConnections({
  required SceneDocument document,
  required KitPort source,
}) {
  final ports = kitPorts(document);
  final rows = <PortConnection>[];
  for (final cable in sceneCables(document)) {
    if (!_touches(cable, source)) {
      continue;
    }
    final other = _otherPort(ports, cable, source);
    final frame = other == null ? null : document.objectById(other.frameId);
    if (other == null || frame == null) {
      continue;
    }
    rows.add(
      PortConnection(
        cable: cable,
        label:
            '${kitDisplayName(document, frame)} · ${kitPortSpecOf(other.kind).label}',
      ),
    );
  }
  final counts = <String, int>{};
  for (final row in rows) {
    counts[row.label] = (counts[row.label] ?? 0) + 1;
  }
  return [
    for (final row in rows)
      PortConnection(
        cable: row.cable,
        label: (counts[row.label] ?? 0) > 1
            ? 'Cut · ${row.label} · ${_otherFrameId(row.cable, source)}'
            : 'Cut · ${row.label}',
      ),
  ];
}

String _otherFrameId(SceneCable cable, KitPort source) {
  return kitPortIsOutput(source.kind) ? cable.targetFrameId : cable.sourceId;
}

/// The cable that already joins this pair, if one is stored.
SceneCable? cableJoining(SceneDocument document, KitPort a, KitPort b) {
  for (final cable in sceneCables(document)) {
    if (_samePair(cable, a, b)) {
      return cable;
    }
  }
  return null;
}

bool _touches(SceneCable cable, KitPort port) {
  if (kitPortIsOutput(port.kind)) {
    return cable.fromKind == port.kind && cable.sourceId == port.frameId;
  }
  return cable.toKind == port.kind && cable.targetFrameId == port.frameId;
}

KitPort? _otherPort(List<KitPort> ports, SceneCable cable, KitPort source) {
  final frameId = kitPortIsOutput(source.kind)
      ? cable.targetFrameId
      : cable.sourceId;
  final kind = kitPortIsOutput(source.kind) ? cable.toKind : cable.fromKind;
  if (kind == null) {
    return null;
  }
  for (final port in ports) {
    if (port.frameId == frameId && port.kind == kind) {
      return port;
    }
  }
  return null;
}

bool _samePair(SceneCable cable, KitPort a, KitPort b) {
  final output = kitPortIsOutput(a.kind) ? a : b;
  final input = identical(output, a) ? b : a;
  return cable.fromKind == output.kind &&
      cable.toKind == input.kind &&
      cable.sourceId == output.frameId &&
      cable.targetFrameId == input.frameId;
}

int _wrap(int index, int length) {
  if (length <= 0) {
    return 0;
  }
  return ((index % length) + length) % length;
}
