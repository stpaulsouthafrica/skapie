import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/agent/llm_kit_mark.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene_object.dart';

/// Places registered scene objects in world space. Does not mutate the scene.
class SceneObjectLayer extends StatelessWidget {
  const SceneObjectLayer({
    super.key,
    required this.camera,
    required this.viewportSize,
    required this.objects,
    required this.registry,
    this.selectedId,
    this.previewDelta = Offset.zero,
    this.previewIds = const {},
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final List<SceneObject> objects;
  final ObjectRegistry registry;
  final String? selectedId;
  final Offset previewDelta;
  final Set<String> previewIds;

  @override
  Widget build(BuildContext context) {
    if (viewportSize.isEmpty) {
      return const SizedBox.expand();
    }
    final ordered = [
      for (final object in objects)
        if (object.visible) object,
    ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [for (final object in ordered) _placed(context, object)],
      ),
    );
  }

  Widget _placed(BuildContext context, SceneObject object) {
    final preview = previewIds.contains(object.id) || object.id == selectedId
        ? previewDelta
        : Offset.zero;
    final topLeft = worldToScreen(
      Offset(object.x + preview.dx, object.y + preview.dy),
      viewportSize,
      camera,
    );
    final ctx = RegistryBuildContext(zoom: camera.zoom);
    Widget child = SizedBox(
      width: object.width * camera.zoom,
      height: object.height * camera.zoom,
      child: registry.build(context, object, ctx: ctx),
    );
    if (object.props[skapieKitProp] == harnessLlmKitId &&
        object.props[skapieRoleProp] == 'frame') {
      child = _llmChrome(context, object, child);
    }
    if (object.rotation != 0) {
      child = Transform.rotate(angle: object.rotation, child: child);
    }
    return Positioned(left: topLeft.dx, top: topLeft.dy, child: child);
  }

  Widget _llmChrome(BuildContext context, SceneObject frame, Widget child) {
    final tokens = PaintScope.of(context);
    final zoom = camera.zoom;
    final barH = (28.0 * zoom).clamp(22.0, 34.0);
    final mark = (12.0 * zoom).clamp(10.0, 16.0);
    final model = _modelForFrame(frame);
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: barH,
          child: ColoredBox(
            key: const Key('llm-kit-chrome'),
            color: tokens.accent.withValues(alpha: 0.22),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8 * zoom),
              child: Row(
                children: [
                  LlmKitMark(
                    key: const Key('llm-kit-mark'),
                    color: tokens.accent,
                    size: mark,
                  ),
                  SizedBox(width: 6 * zoom),
                  Text(
                    'LLM',
                    style: TextStyle(
                      color: tokens.ink,
                      fontSize: (12.0 * zoom).clamp(10.0, 13.0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (model != null) ...[
                    SizedBox(width: 8 * zoom),
                    Expanded(
                      child: Text(
                        model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.muted,
                          fontSize: (11.0 * zoom).clamp(9.0, 12.0),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String? _modelForFrame(SceneObject frame) {
    for (final object in objects) {
      if (!isLlmKitObject(object) ||
          object.props[skapieRoleProp] != 'body' ||
          !llmBodyBelongsToFrame(object, frame)) {
        continue;
      }
      final model = object.props['model']?.toString().trim() ?? '';
      if (model.isEmpty) {
        return null;
      }
      return model;
    }
    return null;
  }
}
