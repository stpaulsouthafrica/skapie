import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/registry/builtin_types.dart';

/// One tool kit on the board. The package carries only look and metadata; the
/// host owns the runner behind the matching [toolName].
class WorldToolKitSpec {
  const WorldToolKitSpec(
    this.toolName,
    this.description, {
    this.requiresRepository = false,
    this.requiresWrite = false,
    this.displayName,
    this.frameHeight,
  });

  final String toolName;
  final String description;
  final bool requiresRepository;
  final bool requiresWrite;
  final String? displayName;
  final double? frameHeight;

  String get label => displayName ?? toolName;
  double get height => frameHeight ?? toolFrameHeight;
}

/// The four starter coding tools. Every other tool kit lives in examples/.
const List<WorldToolKitSpec> worldToolKitSpecs = [
  WorldToolKitSpec(
    'read',
    'List, search, or read files in the connected repository.',
    requiresRepository: true,
    displayName: 'Read',
  ),
  WorldToolKitSpec(
    'write',
    'Create or replace one file in the connected repository.',
    requiresWrite: true,
    displayName: 'Write',
  ),
  WorldToolKitSpec(
    'edit',
    'Replace exact text in one repository file.',
    requiresWrite: true,
    displayName: 'Edit',
  ),
  WorldToolKitSpec(
    'shell',
    'Run a command with the repository as its working folder.',
    requiresWrite: true,
    displayName: 'Shell',
  ),
];

String worldToolKitId(String toolName) => 'tools.$toolName';

String toolDescriptionForKit(String kitId) {
  for (final spec in worldToolKitSpecs) {
    if (worldToolKitId(spec.toolName) == kitId) {
      return spec.description;
    }
  }
  return '';
}

/// Shorten tool cards and seed a description the inspector can edit.
void fitPlacedToolKits(KitApi kitApi) {
  final frames = [
    for (final object in kitApi.store.document.objects)
      if (object.props[skapieRoleProp] == 'frame' &&
          (object.props[skapieKitProp]?.toString().startsWith('tools.') ??
              false))
        object,
  ];
  for (final frame in frames) {
    final description = frame.props['description']?.toString().trim() ?? '';
    if (description.isEmpty) {
      final seeded = toolDescriptionForKit(
        frame.props[skapieKitProp]?.toString() ?? '',
      );
      if (seeded.isNotEmpty) {
        kitApi.updateProps(frame.id, {'description': seeded});
      }
    }
    if ((frame.height - toolFrameHeight).abs() <= 0.5) {
      continue;
    }
    final document = kitApi.store.document;
    for (final object in document.objects) {
      if (object.id == frame.id || !kitChildBelongsToFrame(object, frame)) {
        continue;
      }
      if (object.y + object.height <= frame.y + toolFrameHeight + 0.5) {
        continue;
      }
      kitApi.updateFrame(
        id: object.id,
        y: frame.y + kitBarWorld + 4,
        height: toolFrameHeight - kitBarWorld - 8,
      );
    }
    kitApi.updateFrame(id: frame.id, height: toolFrameHeight);
  }
}

Map<String, Object?> _grantProps(WorldToolKitSpec spec, String id) {
  return {
    if (spec.requiresRepository) 'requiresRepository': true,
    if (spec.requiresWrite) 'requiresWrite': true,
  };
}

Map<String, Object?> worldToolKitJson(WorldToolKitSpec spec) {
  final id = worldToolKitId(spec.toolName);
  return {
    'schemaVersion': 1,
    'id': id,
    'displayName': spec.label,
    'description': spec.description,
    'capabilities': <Object?>[],
    'objects': [
      {
        'typeId': 'box',
        'x': 0,
        'y': 0,
        'width': 200,
        'height': spec.height,
        'props': {
          skapieKitProp: id,
          skapieRoleProp: 'frame',
          'description': spec.description,
          ..._grantProps(spec, id),
        },
      },
      {
        'typeId': 'text',
        'x': 12,
        'y': 36,
        'width': 176,
        'height': 20,
        'props': {
          'content': spec.toolName,
          'fontSize': 14,
          'toolName': spec.toolName,
          attachedToProp: '',
          ..._grantProps(spec, id),
          skapieKitProp: id,
          skapieRoleProp: 'grant',
        },
      },
    ],
  };
}

KitRecipe worldToolKitRecipe(WorldToolKitSpec spec) {
  final id = worldToolKitId(spec.toolName);
  return KitRecipe(
    id: id,
    displayName: spec.label,
    objects: [
      KitObjectSpec(
        typeId: boxTypeId,
        x: 0,
        y: 0,
        width: 200,
        height: spec.height,
        props: {
          skapieKitProp: id,
          skapieRoleProp: 'frame',
          'description': spec.description,
          ..._grantProps(spec, id),
        },
      ),
      KitObjectSpec(
        typeId: textTypeId,
        x: 12,
        y: 36,
        width: 176,
        height: 20,
        props: {
          'content': spec.toolName,
          'fontSize': 14,
          'toolName': spec.toolName,
          attachedToProp: '',
          ..._grantProps(spec, id),
          skapieKitProp: id,
          skapieRoleProp: 'grant',
        },
      ),
    ],
  );
}

void registerWorldToolKits(KitApi kitApi) {
  for (final spec in worldToolKitSpecs) {
    kitApi.registerKit(worldToolKitRecipe(spec));
  }
}
