import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/scene_object_layer.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene_object.dart';

void main() {
  const viewport = Size(800, 600);

  const frame = SceneObject(
    id: 'frame',
    type: 'box',
    x: -160,
    y: -130,
    width: 320,
    height: 260,
    props: {
      skapieKitProp: harnessLlmKitId,
      skapieRoleProp: 'frame',
      'cornerRadius': 22,
    },
  );
  const body = SceneObject(
    id: 'body',
    type: 'text',
    x: -148,
    y: -118,
    width: 296,
    height: 236,
    props: {
      skapieKitProp: harnessLlmKitId,
      skapieRoleProp: 'body',
      'content': 'Input',
      'prompt': '',
    },
  );

  Future<void> pumpLayer(
    WidgetTester tester, {
    required double zoom,
    String? selectedId,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: SizedBox.fromSize(
          size: viewport,
          child: SceneObjectLayer(
            camera: CanvasCamera(zoom: zoom),
            viewportSize: viewport,
            objects: const [frame, body],
            registry: createBuiltinRegistry(),
            selectedId: selectedId,
          ),
        ),
      ),
    );
  }

  testWidgets('unknown types render a placeholder in the layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.fromSize(
          size: viewport,
          child: SceneObjectLayer(
            camera: CanvasCamera(),
            viewportSize: viewport,
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

  testWidgets('LLM chrome scales with zoom and selection does not resize it', (
    tester,
  ) async {
    await pumpLayer(tester, zoom: 1);
    final full = tester.getSize(find.byKey(const Key('llm-kit-chrome')));
    final card = tester.getSize(find.byKey(const ValueKey('kit-card-frame')));

    await pumpLayer(tester, zoom: 0.5);
    final half = tester.getSize(find.byKey(const Key('llm-kit-chrome')));
    expect(half.height, closeTo(full.height / 2, 0.01));
    expect(half.width, closeTo(full.width / 2, 0.01));
    expect(tester.takeException(), isNull);

    await pumpLayer(tester, zoom: 1, selectedId: 'body');
    expect(tester.getSize(find.byKey(const ValueKey('kit-card-frame'))), card);
    expect(tester.getSize(find.byKey(const Key('llm-kit-chrome'))), full);
  });
}
