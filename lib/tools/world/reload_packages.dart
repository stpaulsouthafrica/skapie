import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool reloadPackagesTool(KitApi kitApi) {
  return AgentTool(
    name: 'reload_packages',
    description: 'Reload kit packages from disk.',
    parameters: jsonSchemaObject(),
    run: (_) async {
      await kitApi.reloadPackages();
      return {'ok': true, 'count': kitApi.listKits().length};
    },
  );
}
