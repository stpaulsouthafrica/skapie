import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool updateFrameTool(KitApi kitApi) {
  return AgentTool(
    name: 'update_frame',
    description: 'Patch a scene object frame.',
    parameters: jsonSchemaObject(
      properties: {
        'id': objectIdSchema,
        'x': {'type': 'number'},
        'y': {'type': 'number'},
        'width': {'type': 'number'},
        'height': {'type': 'number'},
        'rotation': {'type': 'number'},
      },
      required: const ['id'],
    ),
    run: (args) async {
      kitApi.updateFrame(
        id: requiredString(args, 'id'),
        x: optionalDouble(args, 'x'),
        y: optionalDouble(args, 'y'),
        width: optionalDouble(args, 'width'),
        height: optionalDouble(args, 'height'),
        rotation: optionalDouble(args, 'rotation'),
      );
      return {'ok': true};
    },
  );
}
