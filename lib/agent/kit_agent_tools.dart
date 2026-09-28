import 'package:skapie/agent/agent_tool.dart';
import 'package:skapie/kit_api/kit_api.dart';

export 'package:skapie/tools/tool.dart';

/// Tools injected from package `kit.dart` files on the loaded shelf.
List<AgentTool> createKitAgentTools(KitApi kitApi) => kitApi.packageAgentTools;
