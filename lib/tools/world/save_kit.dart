import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/tool.dart';

AgentTool saveKitTool(KitApi kitApi) {
  return AgentTool(
    name: 'save_kit',
    description: 'Write a kit package to disk and register it.',
    parameters: kitRecipeSchema,
    run: (args) async {
      final recipe = recipeFromArgs(args);
      await kitApi.saveKit(recipe);
      return {'ok': true, 'id': recipe.id};
    },
  );
}
