import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool removeObjectTool(KitApi kitApi) {
  return AgentTool(
    name: 'remove_object',
    description: 'Remove a scene object by id.',
    parameters: jsonSchemaObject(
      properties: {'id': objectIdSchema},
      required: const ['id'],
    ),
    run: (args) async {
      kitApi.removeObject(requiredString(args, 'id'));
      return {'ok': true};
    },
  );
}
