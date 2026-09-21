import 'package:skapie/agent/agent_tool.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/world/register.dart';

export 'package:skapie/tools/tool.dart';
export 'package:skapie/tools/world/register.dart';

/// Thin wrapper. World tools live under `lib/tools/world/`.
List<AgentTool> createKitAgentTools(KitApi kitApi) => createWorldTools(kitApi);
