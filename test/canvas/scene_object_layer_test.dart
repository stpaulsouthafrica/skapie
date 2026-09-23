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
    expect(
      tester.getCenter(find.byKey(const Key('llm-kit-status'))).dy,
      closeTo(tester.getCenter(find.text('Output')).dy, 0.5),
    );
  });

  testWidgets('a text kit shows two lines and In and Out under a rule', (
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
                id: 'text-frame',
                type: 'box',
                x: -140,
                y: -75,
                width: 280,
                height: 150,
                props: {skapieKitProp: boardTextKitId, skapieRoleProp: 'frame'},
              ),
              SceneObject(
                id: 'text-body',
                type: 'text',
                x: -128,
                y: -31,
                width: 256,
                height: 90,
                props: {
                  skapieKitProp: boardTextKitId,
                  skapieRoleProp: 'body',
                  'content': 'Hello\nsecond\nthird\nfourth',
                },
              ),
            ],
            registry: createBuiltinRegistry(),
          ),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('+3 Lines'), findsOneWidget);
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('second'), findsNothing);
  });

  testWidgets('a conversation kit previews the first line and +N Lines', (
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
                id: 'conversation-frame',
                type: 'box',
                x: -140,
                y: -75,
                width: 280,
                height: 120,
                props: {
                  skapieKitProp: harnessConversationKitId,
                  skapieRoleProp: 'frame',
                },
              ),
              SceneObject(
                id: 'conversation-body',
                type: 'text',
                x: -128,
                y: -35,
                width: 256,
                height: 48,
                props: {
                  skapieKitProp: harnessConversationKitId,
                  skapieRoleProp: 'body',
                  'content': 'User\nlist repo files.\n\nAssistant\nNo tool.',
                },
              ),
            ],
            registry: createBuiltinRegistry(),
          ),
        ),
      ),
    );

    expect(find.text('User'), findsOneWidget);
    expect(find.text('+4 Lines'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('list repo files.'), findsNothing);
    expect(find.text('In'), findsNothing);
  });
}
