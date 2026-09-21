import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool setLockedTool(KitApi kitApi) {
  return AgentTool(
    name: 'set_locked',
    description: 'Set SceneObject.locked.',
    parameters: jsonSchemaObject(
      properties: {
        'id': objectIdSchema,
        'locked': {'type': 'boolean'},
      },
      required: const ['id', 'locked'],
    ),
    run: (args) async {
      kitApi.setLocked(
        requiredString(args, 'id'),
        requiredBool(args, 'locked'),
      );
      return {'ok': true};
    },
  );
}
