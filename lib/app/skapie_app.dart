import 'package:flutter/material.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/agent_provider.dart';
import 'package:skapie/app/home_screen.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene_store.dart';
import 'package:skapie/shared/app_info.dart';

class SkapieApp extends StatelessWidget {
  SkapieApp({
    Key? key,
    required SceneStore store,
    ObjectRegistry? registry,
    KitApi? kitApi,
    AgentSession? agentSession,
    AgentController? agentController,
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
       );

  SkapieApp._({
    super.key,
    required this.store,
    required this.kitApi,
    AgentSession? agentSession,
    AgentController? agentController,
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
  ObjectRegistry get registry => kitApi.registry;

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
          store: store,
          registry: registry,
          kitApi: kitApi,
          agentController: agentController,
        ),
      ),
    );
  }
}
