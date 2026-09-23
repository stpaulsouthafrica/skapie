import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/registry/builtin_types.dart';

class WorldToolKitSpec {
  const WorldToolKitSpec(
    this.toolName,
    this.description, {
    this.requiresRepository = false,
  });

  final String toolName;
  final String description;
  final bool requiresRepository;
}

const List<WorldToolKitSpec> worldToolKitSpecs = [
  WorldToolKitSpec('list_kits', 'List registered kits.'),
  WorldToolKitSpec('get_kit', 'Get one kit recipe by id.'),
  WorldToolKitSpec('instantiate_kit', 'Instantiate a kit into the scene.'),
  WorldToolKitSpec('add_object', 'Add one scene object.'),
  WorldToolKitSpec('remove_object', 'Remove a scene object by id.'),
  WorldToolKitSpec('update_frame', 'Patch a scene object frame.'),
  WorldToolKitSpec(
    'update_props',
    'Shallow-merge props. Null values remove keys.',
  ),
  WorldToolKitSpec('set_locked', 'Set SceneObject.locked.'),
  WorldToolKitSpec('save_kit', 'Write a kit package to disk and register it.'),
  WorldToolKitSpec('reload_packages', 'Reload kit packages from disk.'),
  WorldToolKitSpec('register_kit', 'Register an ephemeral in-memory kit.'),
  WorldToolKitSpec(
    'repo_list_files',
    'List source files in the connected repository.',
    requiresRepository: true,
  ),
  WorldToolKitSpec(
    'repo_search_text',
    'Search text in the connected repository.',
    requiresRepository: true,
  ),
  WorldToolKitSpec(
    'repo_read_file',
    'Read a bounded range of a repository file.',
    requiresRepository: true,
  ),
  WorldToolKitSpec(
    'repo_git_status',
    'Read Git branch and working tree status.',
    requiresRepository: true,
  ),
  WorldToolKitSpec(
    'repo_git_diff',
    'Read a bounded Git diff.',
    requiresRepository: true,
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

Map<String, Object?> worldToolKitJson(WorldToolKitSpec spec) {
  final id = worldToolKitId(spec.toolName);
  return {
    'schemaVersion': 1,
    'id': id,
    'displayName': spec.toolName,
    'description': spec.description,
    'capabilities': <Object?>[],
    'objects': [
      {
        'typeId': 'box',
        'x': 0,
        'y': 0,
        'width': 200,
        'height': toolFrameHeight,
        'props': {
          skapieKitProp: id,
          skapieRoleProp: 'frame',
          'description': spec.description,
          if (spec.requiresRepository) 'requiresRepository': true,
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
          if (spec.requiresRepository) 'requiresRepository': true,
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
    displayName: spec.toolName,
    objects: [
      KitObjectSpec(
        typeId: boxTypeId,
        x: 0,
        y: 0,
        width: 200,
        height: toolFrameHeight,
        props: {
          skapieKitProp: id,
          skapieRoleProp: 'frame',
          'description': spec.description,
          if (spec.requiresRepository) 'requiresRepository': true,
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
          if (spec.requiresRepository) 'requiresRepository': true,
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
