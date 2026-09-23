import 'package:flutter/material.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/home_screen.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/tools/world/kits.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene_store.dart';
import 'package:skapie/scene/scene_persistence.dart';
import 'package:skapie/scene/board_catalog.dart';
import 'package:skapie/shared/app_info.dart';

class SkapieApp extends StatefulWidget {
  SkapieApp({
    Key? key,
    required SceneStore store,
    ObjectRegistry? registry,
    KitApi? kitApi,
    AgentSession? agentSession,
    AgentController? agentController,
    BoardCatalog? boardCatalog,
  }) : this._(
         key: key,
         store: store,
         kitApi:
             kitApi ??
             createAppKitApi(
               store: store,
               registry: registry ?? createBuiltinRegistry(),
             ),
         agentSession: agentSession,
         agentController: agentController,
         boardCatalog: boardCatalog,
       );

  SkapieApp._({
    super.key,
    required this.store,
    required this.kitApi,
    AgentSession? agentSession,
    AgentController? agentController,
    this.boardCatalog,
  }) : agentController =
           agentController ??
           AgentController(
             kitApi: kitApi,
             session:
                 agentSession ??
                 AgentSession(model: const FakeAgentModel(), kitApi: kitApi),
             runtime: const ResolvedAgentRuntime(
               presetId: 'fake',
               useFake: true,
             ),
           );

  final SceneStore store;
  final KitApi kitApi;
  final AgentController agentController;
  final BoardCatalog? boardCatalog;
  ObjectRegistry get registry => kitApi.registry;

  @override
  State<SkapieApp> createState() => _SkapieAppState();
}

class _SkapieAppState extends State<SkapieApp> {
  late SceneStore _store = widget.store;
  late KitApi _kitApi = widget.kitApi;
  late AgentController _controller = widget.agentController;

  Future<void> _openBoard(BoardInfo board) async {
    if (_controller.runningBodyId != null) {
      throw StateError('Wait for the current run to finish.');
    }
    if (_store.sceneFilePath == board.file.absolute.path) {
      return;
    }
    await _store.save();
    final nextStore = SceneStore(persistence: SceneFilePersistence(board.file));
    await nextStore.load();
    final nextKitApi = createAppKitApi(
      store: nextStore,
      registry: _kitApi.registry,
      packages: _kitApi.packages,
    );
    await nextKitApi.reloadPackages();
    fitPlacedLlmKits(nextKitApi);
    fitPlacedToolKits(nextKitApi);
    fitPlacedTextKits(nextKitApi);
    final runtime = _controller.runtime;
    final session = buildAgentSession(kitApi: nextKitApi, runtime: runtime);
    final nextController = AgentController(
      kitApi: nextKitApi,
      session: session,
      vanilla: buildVanillaClient(runtime: runtime, sessionId: session.id),
      runtime: runtime,
      prefsStore: _controller.prefsStore,
      sources: _controller.sources,
      memoryApiKey: _controller.memoryApiKey,
      prefs: _controller.prefs,
      repositoryPermission: _controller.repositoryPermission,
    );
    nextController.rememberCatalog(_controller.catalogModels);
    if (!mounted) {
      return;
    }
    await widget.boardCatalog?.activate(board);
    setState(() {
      _store = nextStore;
      _kitApi = nextKitApi;
      _controller = nextController;
    });
  }

  Future<void> _newBoard() async {
    final catalog = widget.boardCatalog;
    if (catalog == null) {
      return;
    }
    if (_controller.runningBodyId != null) {
      throw StateError('Wait for the current run to finish.');
    }
    await _openBoard(await catalog.create());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PaintTokens.dark();
    return PaintScope(
      tokens: tokens,
      child: MaterialApp(
        title: AppInfo.windowTitle,
        theme: paintTheme(tokens),
        debugShowCheckedModeBanner: false,
        home: HomeScreen(
          key: ValueKey(_store.sceneFilePath ?? _store.document.id),
          store: _store,
          registry: _kitApi.registry,
          kitApi: _kitApi,
          agentController: _controller,
          onNewBoard: widget.boardCatalog == null ? null : _newBoard,
          listBoards: widget.boardCatalog?.list,
          onOpenBoard: widget.boardCatalog == null ? null : _openBoard,
        ),
      ),
    );
  }
}
