import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool listKitsTool(KitApi kitApi) {
  return AgentTool(
    name: 'list_kits',
    description: 'List registered kits.',
    parameters: jsonSchemaObject(),
    run: (_) async {
      return {
        'kits': [
          for (final kit in kitApi.listKits())
            {'id': kit.id, 'displayName': kit.displayName},
        ],
      };
    },
  );
}
