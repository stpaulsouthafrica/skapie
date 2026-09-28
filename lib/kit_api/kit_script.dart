import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_coding_hooks.dart';
import 'package:skapie/kit_api/kit_script_ops.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';
import 'package:skapie/tools/tool.dart';

const _library = 'package:skapie_kit/host.dart';
const _entryLibrary = 'package:kit/main.dart';
const _cacheVersion = 'skapie-kit-script-v1';

/// A tool whose program lives in a package `kit.dart`.
class KitToolBinding {
  const KitToolBinding({
    this.readPath = '',
    this.writePath = '',
    this.readPermission = const SystemRepositoryPermission(),
    this.writePermission = const SystemPatchWritePermission(),
  });

  final String readPath;
  final String writePath;
  final RepositoryPermission readPermission;
  final PatchWritePermission writePermission;
}

class PackageTool {
  PackageTool({
    required this.kitId,
    required this.name,
    required this.description,
    required this.parameters,
    required this.grant,
    required this._run,
  });

  final String kitId;
  final String name;
  final String description;
  final Map<String, Object?> parameters;

  /// `read`, `write`, or empty when the tool needs no folder grant.
  final String grant;
  final Future<Map<String, Object?>> Function(
    Map<String, Object?> args,
    KitToolBinding binding,
  )
  _run;

  AgentTool toAgentTool([
    KitToolBinding binding = const KitToolBinding(),
  ]) {
    return AgentTool(
      name: name,
      description: description,
      parameters: parameters,
      run: (args) => _run(args, binding),
    );
  }
}

/// Read `kit.dart` beside each loaded package and register its tools.
///
/// [onlyIds] limits the scan to packages whose `kit.json` already loaded.
/// Folders without `kit.dart` stay look-only.
void loadPackageScripts(
  KitApi api,
  Directory root, {
  Set<String>? onlyIds,
}) {
  final tools = <PackageTool>[];
  if (!root.existsSync()) {
    api.setPackageTools(tools);
    return;
  }
  final dirs = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in dirs) {
    final kitId = dir.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (onlyIds != null && !onlyIds.contains(kitId)) {
      continue;
    }
    final file = File('${dir.path}/kit.dart');
    if (!file.existsSync()) {
      continue;
    }
    try {
      tools.addAll(_loadOne(api, kitId, file.readAsStringSync()));
      api.statusLog?.clear('package-script:$kitId');
    } catch (error) {
      final message = 'Could not load kit.dart for $kitId: $error';
      api.log?.call(message);
      api.statusLog?.report(key: 'package-script:$kitId', message: message);
    }
  }
  api.setPackageTools(tools);
}

List<PackageTool> _loadOne(KitApi api, String kitId, String source) {
  final session = _KitScriptSession(api, kitId);
  final plugin = _KitScriptPlugin(session);
  final runtime = _runtimeFor(source, plugin);
  session.runtime = runtime;
  runtime.executeLib(_entryLibrary, 'register');
  return session.tools;
}

Runtime _runtimeFor(String source, _KitScriptPlugin plugin) {
  final cached = _programs[source];
  final Runtime runtime;
  if (cached != null) {
    runtime = Runtime.ofProgram(cached);
  } else {
    final file = _cacheFile(source);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      runtime = Runtime(
        bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length),
      );
    } else {
      final program = _compile(source);
      _programs[source] = program;
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(program.write());
      runtime = Runtime.ofProgram(program);
    }
  }
  runtime.addPlugin(plugin);
  return runtime;
}

final Map<String, Program> _programs = {};

Program _compile(String source) {
  final compiler = Compiler();
  compiler.addPlugin(_KitScriptPlugin(null));
  return compiler.compile({
    'kit': {'main.dart': source},
  });
}

File _cacheFile(String source) {
  final digest = sha256.convert(utf8.encode('$_cacheVersion\n$source'));
  return File(
    '${Directory.systemTemp.path}/skapie-kit-scripts/${digest.toString()}.evc',
  );
}

class _KitScriptSession {
  _KitScriptSession(this.api, this.kitId);

  final KitApi api;
  final String kitId;
  Runtime? runtime;
  final List<PackageTool> tools = [];
}

class _KitScriptPlugin implements EvalPlugin {
  _KitScriptPlugin(this.session);

  final _KitScriptSession? session;

  @override
  String get identifier => 'skapie_kit';

  @override
  void configureForCompile(BridgeDeclarationRegistry registry) {
    registry.defineBridgeTopLevelFunction(
      _declare('addTool', CoreTypes.voidType, [
        _param('name'),
        _param('description'),
        _param('parametersJson'),
        _param('grant'),
      ]),
    );
    registry.defineBridgeTopLevelFunction(
      _declare('call', CoreTypes.string, [_param('op'), _param('argsJson')]),
    );
  }

  @override
  void configureForRuntime(Runtime runtime) {
    final session = this.session;
    runtime.registerBridgeFunc(_library, 'addTool', (rt, target, args) {
      if (session == null) {
        return null;
      }
      session.addTool(
        _text(args, 0),
        _text(args, 1),
        _text(args, 2),
        _text(args, 3),
      );
      return null;
    });
    runtime.registerBridgeFunc(_library, 'call', (rt, target, args) {
      if (session == null) {
        return $String('{}');
      }
      return $String(runKitOp(session.api, _text(args, 0), _text(args, 1)));
    });
  }
}

extension on _KitScriptSession {
  void addTool(
    String name,
    String description,
    String parametersJson,
    String grant,
  ) {
    final decoded = jsonDecode(parametersJson);
    if (decoded is! Map) {
      throw FormatException('Tool $name parameters must be a JSON object');
    }
    final runtime = this.runtime;
    if (runtime == null) {
      throw StateError('Kit script runtime is not ready');
    }
    tools.add(
      PackageTool(
        kitId: kitId,
        name: name,
        description: description,
        parameters: Map<String, Object?>.from(decoded),
        grant: grant,
        run: (args, binding) => _runTool(runtime, name, args, binding),
      ),
    );
  }

  Future<Map<String, Object?>> _runTool(
    Runtime runtime,
    String name,
    Map<String, Object?> args,
    KitToolBinding binding,
  ) async {
    final result = runtime.executeLib(_entryLibrary, 'runTool', [
      $String(name),
      $String(jsonEncode(args)),
      $String(
        jsonEncode({
          'readPath': binding.readPath,
          'writePath': binding.writePath,
        }),
      ),
    ]);
    return _finish(api, _unwrap(result), binding);
  }
}

Future<Map<String, Object?>> _finish(
  KitApi api,
  String raw,
  KitToolBinding binding,
) async {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('kit.dart runTool must return a JSON object');
  }
  final map = Map<String, Object?>.from(decoded);
  final args = map['args'];
  final toolArgs = args is Map
      ? Map<String, Object?>.from(args)
      : const <String, Object?>{};
  switch (map['__defer']?.toString()) {
    case 'saveKit':
      final recipe = recipeFromArgs(toolArgs);
      await api.saveKit(recipe);
      return {'ok': true, 'id': recipe.id};
    case 'reloadPackages':
      await api.reloadPackages();
      return {'ok': true, 'count': api.listKits().length};
    case 'read':
      return runReadHook(
        path: binding.readPath,
        args: toolArgs,
        permission: binding.readPermission,
      );
    case 'write':
      return runWriteHook(
        path: binding.writePath,
        args: toolArgs,
        permission: binding.writePermission,
      );
    case 'edit':
      return runEditHook(
        path: binding.writePath,
        args: toolArgs,
        permission: binding.writePermission,
      );
    case 'shell':
      return runShellHook(
        path: binding.writePath,
        args: toolArgs,
        permission: binding.writePermission,
      );
    default:
      return map;
  }
}

String _unwrap(Object? result) {
  if (result is $String) {
    return result.$value;
  }
  if (result is String) {
    return result;
  }
  if (result is $Value) {
    final reified = result.$reified;
    if (reified is String) {
      return reified;
    }
  }
  throw const FormatException('kit.dart runTool must return a JSON string');
}

String _text(List<$Value?> args, int index) {
  final value = args[index];
  if (value is $String) {
    return value.$value;
  }
  return value?.$reified?.toString() ?? '';
}

BridgeTypeAnnotation get _string =>
    BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string));

BridgeParameter _param(String name) {
  return BridgeParameter(name, _string, false);
}

BridgeFunctionDeclaration _declare(
  String name,
  BridgeTypeSpec returnsType,
  List<BridgeParameter> params,
) {
  return BridgeFunctionDeclaration(
    _library,
    name,
    BridgeFunctionDef(
      returns: BridgeTypeAnnotation(BridgeTypeRef(returnsType)),
      params: params,
    ),
  );
}
