import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool addObjectTool(KitApi kitApi) {
  return AgentTool(
    name: 'add_object',
    description: 'Add one scene object.',
    parameters: jsonSchemaObject(
      properties: {
        'typeId': {'type': 'string'},
        'x': {'type': 'number'},
        'y': {'type': 'number'},
        'width': {'type': 'number'},
        'height': {'type': 'number'},
        'props': {'type': 'object', 'additionalProperties': true},
      },
      required: const ['typeId'],
    ),
    run: (args) async {
      final id = kitApi.addObject(
        typeId: requiredString(args, 'typeId'),
        x: optionalDouble(args, 'x') ?? 0,
        y: optionalDouble(args, 'y') ?? 0,
        width: optionalDouble(args, 'width'),
        height: optionalDouble(args, 'height'),
        props: readProps(args['props']),
      );
      return {'id': id};
    },
  );
}
