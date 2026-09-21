import 'package:skapie/agent/agent_tool.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/world/add_object.dart';
import 'package:skapie/tools/world/get_kit.dart';
import 'package:skapie/tools/world/instantiate_kit.dart';
import 'package:skapie/tools/world/list_kits.dart';
import 'package:skapie/tools/world/register_kit.dart';
import 'package:skapie/tools/world/reload_packages.dart';
import 'package:skapie/tools/world/remove_object.dart';
import 'package:skapie/tools/world/save_kit.dart';
import 'package:skapie/tools/world/set_locked.dart';
import 'package:skapie/tools/world/update_frame.dart';
import 'package:skapie/tools/world/update_props.dart';

List<AgentTool> createWorldTools(KitApi kitApi) {
  return [
    listKitsTool(kitApi),
    getKitTool(kitApi),
    instantiateKitTool(kitApi),
    addObjectTool(kitApi),
    removeObjectTool(kitApi),
    updateFrameTool(kitApi),
    updatePropsTool(kitApi),
    setLockedTool(kitApi),
    saveKitTool(kitApi),
    reloadPackagesTool(kitApi),
    registerKitTool(kitApi),
  ];
}
