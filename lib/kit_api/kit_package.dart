import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/object_registry.dart';
import 'package:skapie/scene/scene_json_codec.dart';

const int kitPackageSchemaVersion = 1;

const Map<String, Object?> demoNoteCardJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': demoNoteCardKitId,
  'displayName': 'Note card',
  'description': 'A box with inset text.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 200,
      'height': 88,
      'props': <String, Object?>{},
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 16,
      'width': 176,
      'height': 56,
      'props': {'content': 'Note'},
    },
  ],
};

const Map<String, Object?> harnessLlmJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': harnessLlmKitId,
  'displayName': 'LLM',
  'description':
      'Compound vanilla kit: Input and Output regions. No animation.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 320,
      'height': 320,
      'props': {skapieKitProp: harnessLlmKitId, skapieRoleProp: 'frame'},
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 12,
      'width': 296,
      'height': 296,
      'props': {
        'content': 'Input\n\nOutput\n\nTools: none',
        'fontSize': 14,
        'prompt': '',
        'reply': '',
        'error': '',
        'model': '',
        'provider': '',
        'surface': '',
        skapieKitProp: harnessLlmKitId,
        skapieRoleProp: 'body',
      },
    },
  ],
};

const Map<String, Object?> harnessSystemPromptJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': harnessSystemPromptKitId,
  'displayName': 'System prompt',
  'description': 'Stub system prompt kit. Wiring is later.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': 140,
      'props': {
        skapieKitProp: harnessSystemPromptKitId,
        skapieRoleProp: 'frame',
      },
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 16,
      'width': 256,
      'height': 108,
      'props': {
        'content': 'System prompt',
        'fontSize': 14,
        attachedToProp: '',
        skapieKitProp: harnessSystemPromptKitId,
        skapieRoleProp: 'prompt',
      },
    },
  ],
};

const Map<String, Object?> harnessToolsJson = {
  'schemaVersion': kitPackageSchemaVersion,
  'id': harnessToolsKitId,
  'displayName': 'Tools',
  'description': 'Stub tools kit. Wiring is later.',
  'capabilities': <Object?>[],
  'objects': [
    {
      'typeId': 'box',
      'x': 0,
      'y': 0,
      'width': 280,
      'height': 180,
      'props': {skapieKitProp: harnessToolsKitId, skapieRoleProp: 'frame'},
    },
    {
      'typeId': 'text',
      'x': 12,
      'y': 16,
      'width': 256,
      'height': 148,
      'props': {
        'content': 'Kit tools (stub)\n\n$harnessToolsRoster',
        'fontSize': 14,
        'toolNames': harnessToolsRoster,
        attachedToProp: '',
        skapieKitProp: harnessToolsKitId,
        skapieRoleProp: 'tools',
      },
    },
  ],
};

class ParsedKitPackage {
  const ParsedKitPackage({
    required this.schemaVersion,
    required this.recipe,
    this.description,
    this.capabilities = const [],
    this.capabilityWarning,
  });

  final int schemaVersion;
  final KitRecipe recipe;
  final String? description;
  final List<String> capabilities;
  final String? capabilityWarning;
}

bool isValidKitId(String id) {
  if (id.isEmpty || id == '.' || id == '..') {
    return false;
  }
  return !id.contains('/') && !id.contains('\\');
}

ParsedKitPackage parseKitPackageJson(
  Map<String, Object?> json, {
  required String folderId,
  ObjectRegistry? registry,
}) {
  final version = json['schemaVersion'];
  if (version is! num) {
    throw const FormatException('kit.json schemaVersion is required');
  }
  if (version.toInt() != kitPackageSchemaVersion) {
    throw FormatException('Unsupported kit schemaVersion: $version');
  }
  final id = json['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('kit.json id is required');
  }
  if (!isValidKitId(id)) {
    throw FormatException('Invalid kit id: $id');
  }
  if (id != folderId) {
    throw FormatException(
      'kit.json id "$id" does not match folder "$folderId"',
    );
  }
  final displayName = json['displayName'];
  if (displayName is! String || displayName.isEmpty) {
    throw const FormatException('kit.json displayName is required');
  }
  final description = json['description'];
  final capabilities = _readCapabilities(json['capabilities']);
  final objects = _readObjects(json['objects'], registry: registry);
  String? warning;
  if (capabilities.isNotEmpty) {
    warning =
        'Kit $id has capabilities $capabilities; Phase 7 loads declarative objects only.';
  }
  return ParsedKitPackage(
    schemaVersion: version.toInt(),
    recipe: KitRecipe(id: id, displayName: displayName, objects: objects),
    description: description is String ? description : null,
    capabilities: capabilities,
    capabilityWarning: warning,
  );
}

Map<String, Object?> kitPackageToJson(ParsedKitPackage package) {
  return {
    'schemaVersion': package.schemaVersion,
    'id': package.recipe.id,
    'displayName': package.recipe.displayName,
    if (package.description != null) 'description': package.description,
    'capabilities': package.capabilities,
    'objects': [
      for (final object in package.recipe.objects) _objectToJson(object),
    ],
  };
}

ParsedKitPackage packageFromRecipe(KitRecipe recipe) {
  return ParsedKitPackage(
    schemaVersion: kitPackageSchemaVersion,
    recipe: recipe,
    capabilities: const [],
  );
}

List<String> _readCapabilities(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw const FormatException('kit.json capabilities must be an array');
  }
  return [
    for (final item in value)
      if (item is String) item,
  ];
}

List<KitObjectSpec> _readObjects(Object? value, {ObjectRegistry? registry}) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw const FormatException('kit.json objects must be an array');
  }
  return [
    for (final item in value)
      _readObject(asJsonMap(item, 'objects[]'), registry: registry),
  ];
}

KitObjectSpec _readObject(
  Map<String, Object?> json, {
  ObjectRegistry? registry,
}) {
  final typeId = json['typeId'];
  if (typeId is! String || typeId.isEmpty) {
    throw const FormatException('object typeId is required');
  }
  if (registry != null && registry.get(typeId) == null) {
    throw FormatException('Unknown typeId: $typeId');
  }
  return KitObjectSpec(
    typeId: typeId,
    x: readDouble(json, 'x', 0),
    y: readDouble(json, 'y', 0),
    width: json.containsKey('width') ? readDouble(json, 'width') : null,
    height: json.containsKey('height') ? readDouble(json, 'height') : null,
    props: readProps(json['props']),
  );
}

Map<String, Object?> _objectToJson(KitObjectSpec object) {
  return {
    'typeId': object.typeId,
    'x': object.x,
    'y': object.y,
    if (object.width != null) 'width': object.width,
    if (object.height != null) 'height': object.height,
    'props': object.props,
  };
}
