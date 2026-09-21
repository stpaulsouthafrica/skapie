import 'package:flutter/material.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/app/home_screen.dart';
import 'package:skapie/app/theme.dart';
import 'package:skapie/kit_api/kit_api.dart';
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
       );

  SkapieApp._({
    super.key,
    required this.store,
    required this.kitApi,
    AgentSession? agentSession,
  }) : agentSession =
           agentSession ??
           AgentSession(model: const FakeAgentModel(), kitApi: kitApi);

  final SceneStore store;
  final KitApi kitApi;
  final AgentSession agentSession;
  ObjectRegistry get registry => kitApi.registry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.windowTitle,
      theme: buildAppTheme(),
      home: HomeScreen(
        store: store,
        registry: registry,
        kitApi: kitApi,
        agentSession: agentSession,
      ),
    );
  }
}
