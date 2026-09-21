import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool registerKitTool(KitApi kitApi) {
  return AgentTool(
    name: 'register_kit',
    description: 'Register an ephemeral in-memory kit.',
    parameters: kitRecipeSchema,
    run: (args) async {
      final recipe = recipeFromArgs(args);
      kitApi.registerKit(recipe);
      return {'ok': true, 'id': recipe.id};
    },
  );
}
