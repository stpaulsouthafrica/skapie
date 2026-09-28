import 'dart:convert';
import 'dart:ui';

import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

/// Host hooks a package `kit.dart` may call. The package chooses the hook.
/// Argument checks live here so every package shares one parser.
String runKitOp(KitApi api, String op, String argsJson) {
  try {
    final args = _args(argsJson);
    final result = switch (op) {
      'listKits' => _listKits(api),
      'getKit' => _getKit(api, args),
      'instantiate' => _instantiate(api, args),
      'addObject' => _addObject(api, args),
      'removeObject' => _removeObject(api, args),
      'updateFrame' => _updateFrame(api, args),
      'updateProps' => _updateProps(api, args),
      'setLocked' => _setLocked(api, args),
      'registerKit' => _registerKit(api, args),
      _ => toolError('Unknown kit hook: $op'),
    };
    return jsonEncode(result);
  } catch (error) {
    return jsonEncode(toolError('$error'));
  }
}

Map<String, Object?> _args(String argsJson) {
  if (argsJson.trim().isEmpty) {
    return const {};
  }
  final decoded = jsonDecode(argsJson);
  if (decoded is! Map) {
    throw const FormatException('Args must be a JSON object');
  }
  return {for (final entry in decoded.entries) entry.key.toString(): entry.value};
}

Map<String, Object?> _listKits(KitApi api) {
  return {
    'kits': [
      for (final kit in api.listKits())
        {'id': kit.id, 'displayName': kit.displayName},
    ],
  };
}

Map<String, Object?> _getKit(KitApi api, Map<String, Object?> args) {
  final kitId = requiredString(args, 'kitId');
  final kit = api.getKit(kitId);
  if (kit == null) {
    return toolError('Unknown kit: $kitId');
  }
  return {'kit': recipeToJson(kit)};
}

Map<String, Object?> _instantiate(KitApi api, Map<String, Object?> args) {
  final ids = api.instantiate(
    requiredString(args, 'kitId'),
    origin: Offset(
      requiredDouble(args, 'originX'),
      requiredDouble(args, 'originY'),
    ),
  );
  return {'ids': ids};
}

Map<String, Object?> _addObject(KitApi api, Map<String, Object?> args) {
  final id = api.addObject(
    typeId: requiredString(args, 'typeId'),
    x: optionalDouble(args, 'x') ?? 0,
    y: optionalDouble(args, 'y') ?? 0,
    width: optionalDouble(args, 'width'),
    height: optionalDouble(args, 'height'),
    props: readProps(args['props']),
  );
  return {'id': id};
}

Map<String, Object?> _removeObject(KitApi api, Map<String, Object?> args) {
  api.removeObject(requiredString(args, 'id'));
  return {'ok': true};
}

Map<String, Object?> _updateFrame(KitApi api, Map<String, Object?> args) {
  api.updateFrame(
    id: requiredString(args, 'id'),
    x: optionalDouble(args, 'x'),
    y: optionalDouble(args, 'y'),
    width: optionalDouble(args, 'width'),
    height: optionalDouble(args, 'height'),
    rotation: optionalDouble(args, 'rotation'),
  );
  return {'ok': true};
}

Map<String, Object?> _updateProps(KitApi api, Map<String, Object?> args) {
  api.updateProps(requiredString(args, 'id'), requiredMap(args, 'patch'));
  return {'ok': true};
}

Map<String, Object?> _setLocked(KitApi api, Map<String, Object?> args) {
  api.setLocked(requiredString(args, 'id'), requiredBool(args, 'locked'));
  return {'ok': true};
}

Map<String, Object?> _registerKit(KitApi api, Map<String, Object?> args) {
  final recipe = recipeFromArgs(args);
  api.registerKit(recipe);
  return {'ok': true, 'id': recipe.id};
}
