import 'dart:ui';

import 'package:skapie/agent/agent_tool.dart';
import 'package:skapie/kit_api/kit_api.dart';

List<AgentTool> createKitAgentTools(KitApi kitApi) {
  return [
    AgentTool(
      name: 'list_kits',
      description: 'List registered kits.',
      run: (_) async {
        return {
          'kits': [
            for (final kit in kitApi.listKits())
              {'id': kit.id, 'displayName': kit.displayName},
          ],
        };
      },
    ),
    AgentTool(
      name: 'get_kit',
      description: 'Get one kit recipe by id.',
      run: (args) async {
        final kitId = requiredString(args, 'kitId');
        final kit = kitApi.getKit(kitId);
        if (kit == null) {
          return toolError('Unknown kit: $kitId');
        }
        return {'kit': recipeToJson(kit)};
      },
    ),
    AgentTool(
      name: 'instantiate_kit',
      description: 'Instantiate a kit into the scene.',
      run: (args) async {
        final ids = kitApi.instantiate(
          requiredString(args, 'kitId'),
          origin: Offset(
            requiredDouble(args, 'originX'),
            requiredDouble(args, 'originY'),
          ),
        );
        return {'ids': ids};
      },
    ),
    AgentTool(
      name: 'add_object',
      description: 'Add one scene object.',
      run: (args) async {
        final id = kitApi.addObject(
          typeId: requiredString(args, 'typeId'),
          x: optionalDouble(args, 'x') ?? 0,
          y: optionalDouble(args, 'y') ?? 0,
          width: optionalDouble(args, 'width'),
          height: optionalDouble(args, 'height'),
          props: readProps(args['props']),
        );
        return {'id': id};
      },
    ),
    AgentTool(
      name: 'remove_object',
      description: 'Remove a scene object by id.',
      run: (args) async {
        kitApi.removeObject(requiredString(args, 'id'));
        return {'ok': true};
      },
    ),
    AgentTool(
      name: 'update_frame',
      description: 'Patch a scene object frame.',
      run: (args) async {
        kitApi.updateFrame(
          id: requiredString(args, 'id'),
          x: optionalDouble(args, 'x'),
          y: optionalDouble(args, 'y'),
          width: optionalDouble(args, 'width'),
          height: optionalDouble(args, 'height'),
          rotation: optionalDouble(args, 'rotation'),
        );
        return {'ok': true};
      },
    ),
    AgentTool(
      name: 'update_props',
      description: 'Shallow-merge props. Null values remove keys.',
      run: (args) async {
        kitApi.updateProps(
          requiredString(args, 'id'),
          requiredMap(args, 'patch'),
        );
        return {'ok': true};
      },
    ),
    AgentTool(
      name: 'set_locked',
      description: 'Set SceneObject.locked.',
      run: (args) async {
        kitApi.setLocked(
          requiredString(args, 'id'),
          requiredBool(args, 'locked'),
        );
        return {'ok': true};
      },
    ),
    AgentTool(
      name: 'save_kit',
      description: 'Write a kit package to disk and register it.',
      run: (args) async {
        final recipe = recipeFromArgs(args);
        await kitApi.saveKit(recipe);
        return {'ok': true, 'id': recipe.id};
      },
    ),
    AgentTool(
      name: 'reload_packages',
      description: 'Reload kit packages from disk.',
      run: (_) async {
        await kitApi.reloadPackages();
        return {'ok': true, 'count': kitApi.listKits().length};
      },
    ),
    AgentTool(
      name: 'register_kit',
      description: 'Register an ephemeral in-memory kit.',
      run: (args) async {
        final recipe = recipeFromArgs(args);
        kitApi.registerKit(recipe);
        return {'ok': true, 'id': recipe.id};
      },
    ),
  ];
}

String requiredString(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected string "$key"');
  }
  return value;
}

double requiredDouble(Map<String, Object?> args, String key) {
  final value = optionalDouble(args, key);
  if (value == null) {
    throw FormatException('Expected number "$key"');
  }
  return value;
}

double? optionalDouble(Map<String, Object?> args, String key) {
  if (!args.containsKey(key) || args[key] == null) {
    return null;
  }
  final value = args[key];
  if (value is! num) {
    throw FormatException('Expected number "$key"');
  }
  return value.toDouble();
}

bool requiredBool(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is! bool) {
    throw FormatException('Expected bool "$key"');
  }
  return value;
}

Map<String, Object?> requiredMap(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is! Map) {
    throw FormatException('Expected object "$key"');
  }
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

Map<String, Object?> readProps(Object? value) {
  if (value == null) {
    return const {};
  }
  if (value is! Map) {
    throw const FormatException('Expected object "props"');
  }
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

KitRecipe recipeFromArgs(Map<String, Object?> args) {
  return KitRecipe(
    id: requiredString(args, 'id'),
    displayName: requiredString(args, 'displayName'),
    objects: readObjectSpecs(args['objects']),
  );
}

List<KitObjectSpec> readObjectSpecs(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw const FormatException('Expected array "objects"');
  }
  final specs = <KitObjectSpec>[];
  for (final item in value) {
    if (item is! Map) {
      throw const FormatException('Expected object in objects[]');
    }
    specs.add(
      readObjectSpec({
        for (final entry in item.entries) entry.key.toString(): entry.value,
      }),
    );
  }
  return specs;
}

KitObjectSpec readObjectSpec(Map<String, Object?> json) {
  return KitObjectSpec(
    typeId: requiredString(json, 'typeId'),
    x: optionalDouble(json, 'x') ?? 0,
    y: optionalDouble(json, 'y') ?? 0,
    width: optionalDouble(json, 'width'),
    height: optionalDouble(json, 'height'),
    props: readProps(json['props']),
  );
}

Map<String, Object?> recipeToJson(KitRecipe recipe) {
  return {
    'id': recipe.id,
    'displayName': recipe.displayName,
    'objects': [
      for (final object in recipe.objects)
        {
          'typeId': object.typeId,
          'x': object.x,
          'y': object.y,
          if (object.width != null) 'width': object.width,
          if (object.height != null) 'height': object.height,
          'props': object.props,
        },
    ],
  };
}
