import 'package:skapie/kit_api/kit_api.dart';

export 'package:skapie/agent/agent_tool.dart';

const Map<String, Object?> objectIdSchema = {
  'type': 'string',
  'description': 'Scene object id',
};

const Map<String, Object?> kitIdSchema = {
  'type': 'string',
  'description': 'Kit id',
};

const Map<String, Object?> objectSpecSchema = {
  'type': 'object',
  'properties': {
    'typeId': {'type': 'string'},
    'x': {'type': 'number'},
    'y': {'type': 'number'},
    'width': {'type': 'number'},
    'height': {'type': 'number'},
    'props': {'type': 'object', 'additionalProperties': true},
  },
  'required': ['typeId'],
  'additionalProperties': false,
};

const Map<String, Object?> kitRecipeSchema = {
  'type': 'object',
  'properties': {
    'id': {'type': 'string'},
    'displayName': {'type': 'string'},
    'objects': {'type': 'array', 'items': objectSpecSchema},
  },
  'required': ['id', 'displayName'],
  'additionalProperties': false,
};

Map<String, Object?> jsonSchemaObject({
  Map<String, Object?> properties = const {},
  List<String> required = const [],
}) {
  return {
    'type': 'object',
    'properties': properties,
    'additionalProperties': false,
    if (required.isNotEmpty) 'required': required,
  };
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
