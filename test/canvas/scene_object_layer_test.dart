import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/scene_object_layer.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene_object.dart';

void main() {
  testWidgets('unknown types render a placeholder in the layer', (
    tester,
  ) async {
    const size = Size(800, 600);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.fromSize(
          size: size,
          child: SceneObjectLayer(
            camera: CanvasCamera(),
            viewportSize: size,
            objects: const [
              SceneObject(
                id: 'u1',
                type: 'mystery.kit',
                x: -40,
                y: -20,
                width: 80,
                height: 40,
              ),
            ],
            registry: ObjectRegistry(),
          ),
        ),
      ),
    );

    expect(find.byType(UnknownObjectPlaceholder), findsOneWidget);
    expect(find.text('mystery.kit'), findsOneWidget);
  });
}
