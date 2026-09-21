import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool updatePropsTool(KitApi kitApi) {
  return AgentTool(
    name: 'update_props',
    description: 'Shallow-merge props. Null values remove keys.',
    parameters: jsonSchemaObject(
      properties: {
        'id': objectIdSchema,
        'patch': {'type': 'object', 'additionalProperties': true},
      },
      required: const ['id', 'patch'],
    ),
    run: (args) async {
      kitApi.updateProps(
        requiredString(args, 'id'),
        requiredMap(args, 'patch'),
      );
      return {'ok': true};
    },
  );
}
