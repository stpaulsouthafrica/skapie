import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_prefs.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/kit_api/kit_path.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

const _scenePathDefine = String.fromEnvironment('SKAPIE_SCENE_PATH');
const _useProjectScene = bool.fromEnvironment('SKAPIE_USE_PROJECT_SCENE');
const _projectRootDefine = String.fromEnvironment('SKAPIE_PROJECT_ROOT');
const _kitsRootDefine = String.fromEnvironment('SKAPIE_KITS_ROOT');
const _agentProviderDefine = String.fromEnvironment('SKAPIE_AGENT_PROVIDER');
const _agentBaseUrlDefine = String.fromEnvironment('SKAPIE_AGENT_BASE_URL');
const _agentApiKeyDefine = String.fromEnvironment('SKAPIE_AGENT_API_KEY');
const _agentModelDefine = String.fromEnvironment('SKAPIE_AGENT_MODEL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await bootstrapSceneStore();
  final kitApi = await bootstrapKitApi(store: store);
  final agentController = await bootstrapAgentController(kitApi: kitApi);
  runApp(
    SkapieApp(store: store, kitApi: kitApi, agentController: agentController),
  );
}

Future<SceneStore> bootstrapSceneStore({
  Directory? appSupportDirectory,
  Directory? cwd,
}) async {
  final appSupport =
      appSupportDirectory ?? await getApplicationSupportDirectory();
  final projectRoot = _projectRootDefine.trim().isNotEmpty
      ? _projectRootDefine
      : Platform.environment['SKAPIE_PROJECT_ROOT'];
  final resolved = resolveScenePath(
    dartDefinePath: _scenePathDefine,
    envPath: Platform.environment['SKAPIE_SCENE_PATH'],
    useProjectScene: _useProjectScene,
    projectRoot: projectRoot,
    appSupportDirectory: appSupport,
  );
  if (resolved.warning != null) {
    debugPrint('Skapie: ${resolved.warning}');
  }
  final migrated = await migrateLegacySceneIfNeeded(
    canonical: resolved.file,
    cwd: cwd,
  );
  if (migrated != null) {
    debugPrint('Skapie migrated scene into ${migrated.absolute.path}');
  }
  debugPrint('Skapie scene file: ${resolved.file.absolute.path}');
  final store = SceneStore(persistence: SceneFilePersistence(resolved.file));
  await store.load();
  return store;
}

Future<KitApi> bootstrapKitApi({
  required SceneStore store,
  Directory? appSupportDirectory,
  ObjectRegistry? registry,
}) async {
  final appSupport =
      appSupportDirectory ?? await getApplicationSupportDirectory();
  final projectRoot = _projectRootDefine.trim().isNotEmpty
      ? _projectRootDefine
      : Platform.environment['SKAPIE_PROJECT_ROOT'];
  final resolved = resolveKitsRoot(
    dartDefinePath: _kitsRootDefine,
    envPath: Platform.environment['SKAPIE_KITS_ROOT'],
    projectRoot: projectRoot,
    appSupportDirectory: appSupport,
  );
  if (resolved.warning != null) {
    debugPrint('Skapie: ${resolved.warning}');
  }
  debugPrint(
    'Skapie kits root: ${resolved.directory.absolute.path} (${resolved.source})',
  );
  final objectRegistry = registry ?? createBuiltinRegistry();
  final api = createAppKitApi(
    store: store,
    registry: objectRegistry,
    packages: KitPackageStore(
      root: resolved.directory,
      registry: objectRegistry,
    ),
  );
  api.log = (message) => debugPrint('Skapie: $message');
  await api.reloadPackages();
  debugPrint('Skapie kit packages in memory: ${api.listKits().length}');
  return api;
}

Future<AgentController> bootstrapAgentController({
  required KitApi kitApi,
  Directory? appSupportDirectory,
}) async {
  final appSupport =
      appSupportDirectory ?? await getApplicationSupportDirectory();
  final prefsStore = AgentPrefsStore(agentPrefsFile(appSupport));
  final prefs = await prefsStore.load();
  final sources = AgentRuntimeSources(
    dartDefineProvider: _agentProviderDefine,
    envProvider: Platform.environment['SKAPIE_AGENT_PROVIDER'] ?? '',
    dartDefineBaseUrl: _agentBaseUrlDefine,
    envBaseUrl: Platform.environment['SKAPIE_AGENT_BASE_URL'] ?? '',
    dartDefineApiKey: _agentApiKeyDefine,
    envApiKey: Platform.environment['SKAPIE_AGENT_API_KEY'] ?? '',
    dartDefineModel: _agentModelDefine,
    envModel: Platform.environment['SKAPIE_AGENT_MODEL'] ?? '',
    environment: Map<String, String>.from(Platform.environment),
  );
  final runtime = mergeAgentRuntime(prefs: prefs, sources: sources);
  if (runtime.warning != null) {
    debugPrint('Skapie: ${runtime.warning}');
  }
  debugPrint(
    runtime.useFake
        ? 'Skapie agent: FakeAgentModel'
        : 'Skapie agent: ${runtime.presetId} model=${runtime.model}',
  );
  return AgentController(
    kitApi: kitApi,
    session: buildAgentSession(kitApi: kitApi, runtime: runtime),
    runtime: runtime,
    prefsStore: prefsStore,
    sources: sources,
    prefs: prefs,
  );
}
