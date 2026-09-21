import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/builtin_types.dart';

class WorldToolKitSpec {
  const WorldToolKitSpec(this.toolName, this.description);

  final String toolName;
  final String description;
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
];

String worldToolKitId(String toolName) => 'tools.$toolName';

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
        'height': 88,
        'props': {skapieKitProp: id, skapieRoleProp: 'frame'},
      },
      {
        'typeId': 'text',
        'x': 12,
        'y': 16,
        'width': 176,
        'height': 56,
        'props': {
          'content': spec.toolName,
          'fontSize': 14,
          'toolName': spec.toolName,
          attachedToProp: '',
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
        height: 88,
        props: {skapieKitProp: id, skapieRoleProp: 'frame'},
      ),
      KitObjectSpec(
        typeId: textTypeId,
        x: 12,
        y: 16,
        width: 176,
        height: 56,
        props: {
          'content': spec.toolName,
          'fontSize': 14,
          'toolName': spec.toolName,
          attachedToProp: '',
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
