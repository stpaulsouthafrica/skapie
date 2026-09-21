import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool getKitTool(KitApi kitApi) {
  return AgentTool(
    name: 'get_kit',
    description: 'Get one kit recipe by id.',
    parameters: jsonSchemaObject(
      properties: {'kitId': kitIdSchema},
      required: const ['kitId'],
    ),
    run: (args) async {
      final kitId = requiredString(args, 'kitId');
      final kit = kitApi.getKit(kitId);
      if (kit == null) {
        return toolError('Unknown kit: $kitId');
      }
      return {'kit': recipeToJson(kit)};
    },
  );
}
