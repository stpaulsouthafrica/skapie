import 'package:skapie/scene/scene_json_codec.dart';

/// Frame prop that carries a package's declared ports onto the scene object.
const String packagePortsProp = 'ports';

/// The host vocabulary a package may name. A package picks from this list; it
/// cannot invent new port kinds. Values are `PortValue` names.
const Map<String, Set<String>> packagePortFlows = {
  'text': {'output'},
};

/// One port a package declares in `kit.json`. Rendered and cabled by the host.
class KitPackagePort {
  const KitPackagePort({
    required this.id,
    required this.value,
    required this.flow,
    this.label,
    this.placement,
    this.side,
  });

  /// Stable endpoint id within the kit.
  final String id;

  /// Port value name, e.g. `text`.
  final String value;

  /// `input` or `output`. Only `output` is supported today.
  final String flow;
  final String? label;

  /// `footer` or `middle`.
  final String? placement;

  /// `left` or `right`.
  final String? side;

  bool get isOutput => flow == 'output';
}

/// Parse the optional `ports` array. Unknown values or directions are errors so
/// a bad package is skipped and reported instead of rendering inert ports.
List<KitPackagePort> parseKitPackagePorts(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw const FormatException('kit.json ports must be an array');
  }
  final ports = <KitPackagePort>[];
  final ids = <String>{};
  final kinds = <String>{};
  for (final item in value) {
    final port = _readPort(asJsonMap(item, 'ports[]'));
    if (!ids.add(port.id)) {
      throw FormatException('Duplicate port id: ${port.id}');
    }
    if (!kinds.add('${port.flow}:${port.value}')) {
      throw FormatException('Duplicate ${port.flow} port: ${port.value}');
    }
    ports.add(port);
  }
  return ports;
}

KitPackagePort _readPort(Map<String, Object?> json) {
  final id = json['id']?.toString().trim() ?? '';
  if (id.isEmpty) {
    throw const FormatException('port id is required');
  }
  final value = json['value']?.toString().trim() ?? '';
  final flows = packagePortFlows[value];
  if (flows == null) {
    throw FormatException('Unsupported port value: $value');
  }
  final flow = json['flow']?.toString().trim() ?? '';
  if (!flows.contains(flow)) {
    throw FormatException('Port $value cannot be an $flow port');
  }
  return KitPackagePort(
    id: id,
    value: value,
    flow: flow,
    label: _optionalText(json['label']),
    placement: _optionalName(
      json['placement'],
      const {'footer', 'middle'},
      'placement',
    ),
    side: _optionalName(json['side'], const {'left', 'right'}, 'side'),
  );
}

String? _optionalName(Object? value, Set<String> allowed, String label) {
  if (value == null) {
    return null;
  }
  final name = value.toString().trim();
  if (!allowed.contains(name)) {
    throw FormatException('Unsupported port $label: $name');
  }
  return name;
}

String? _optionalText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Map<String, Object?> kitPackagePortToJson(KitPackagePort port) {
  return {
    'id': port.id,
    'value': port.value,
    'flow': port.flow,
    if (port.label != null) 'label': port.label,
    if (port.placement != null) 'placement': port.placement,
    if (port.side != null) 'side': port.side,
  };
}

List<Map<String, Object?>> kitPackagePortsToJson(List<KitPackagePort> ports) {
  return [
    for (final port in ports) kitPackagePortToJson(port),
  ];
}
