import 'dart:ui';

import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool instantiateKitTool(KitApi kitApi) {
  return AgentTool(
    name: 'instantiate_kit',
    description: 'Instantiate a kit into the scene.',
    parameters: jsonSchemaObject(
      properties: {
        'kitId': kitIdSchema,
        'originX': {'type': 'number'},
        'originY': {'type': 'number'},
      },
      required: const ['kitId', 'originX', 'originY'],
    ),
    run: (args) async {
      final ids = kitApi.instantiate(
        requiredString(args, 'kitId'),
        origin: Offset(
          requiredDouble(args, 'originX'),
          requiredDouble(args, 'originY'),
        ),
      );
      return {'ids': ids};
    },
  );
}
