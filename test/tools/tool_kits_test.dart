import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_package.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/world/kits.dart';

void main() {
  test('createAppKitApi registers every tools.* kit', () {
    final api = createAppKitApi(store: SceneStore());
    for (final spec in worldToolKitSpecs) {
      final id = worldToolKitId(spec.toolName);
      expect(api.getKit(id), isNotNull, reason: id);
      expect(api.getKit(id)!.displayName, spec.label);
    }
  });

  test('tools.* kit packages parse as grants with attachedTo', () {
    for (final spec in worldToolKitSpecs) {
      final parsed = parseKitPackageJson(
        worldToolKitJson(spec),
        folderId: worldToolKitId(spec.toolName),
      );
      expect(parsed.recipe.id, worldToolKitId(spec.toolName));
      expect(
        parsed.recipe.objects.any(
          (object) =>
              object.props['toolName'] == spec.toolName &&
              object.props.containsKey(attachedToProp),
        ),
        isTrue,
      );
    }
  });
}
