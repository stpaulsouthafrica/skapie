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

    await pumpLayer(tester, zoom: 0.75);
    final smaller = tester.getSize(find.byKey(const Key('llm-kit-chrome')));
    expect(smaller.height, closeTo(full.height * 0.75, 0.01));
    expect(smaller.width, closeTo(full.width * 0.75, 0.01));
    expect(tester.takeException(), isNull);

    await pumpLayer(tester, zoom: 1, selectedId: 'body');
    expect(tester.getSize(find.byKey(const ValueKey('kit-card-frame'))), card);
    expect(tester.getSize(find.byKey(const Key('llm-kit-chrome'))), full);
    expect(
      tester.getCenter(find.byKey(const Key('llm-kit-status'))).dy,
      closeTo(tester.getCenter(find.text('Output')).dy, 0.5),
    );
    final chrome = tester.getRect(find.byKey(const Key('llm-kit-chrome')));
    final button = tester.getRect(find.byKey(const Key('llm-kit-run-button')));
    final title = tester.getCenter(find.text('LLM'));
    final name = tester.getCenter(find.text('select a model'));
    expect(chrome.right - button.right, lessThan(14));
    expect(button.center.dx, greaterThan(chrome.center.dx));
    expect(name.dx, greaterThan(title.dx + 24));
    expect(button.center.dx, greaterThan(name.dx));
    expect(button.center.dx - name.dx, lessThan(name.dx - title.dx));
    expect(button.center.dy, closeTo(chrome.center.dy, 1));
    expect(title.dy, closeTo(chrome.center.dy, 1.5));
    expect(name.dy, closeTo(chrome.center.dy, 1.5));
    expect(
      tester.getCenter(find.byKey(const Key('llm-kit-mark'))).dy,
      closeTo(chrome.center.dy, 1.5),
    );
  });

  testWidgets('zoomed out, an LLM kit is a name and a status', (tester) async {
    await pumpLayer(tester, zoom: kitOverviewZoom - 0.1);

    expect(find.byKey(const Key('kit-overview-frame')), findsOneWidget);
    expect(find.text('LLM'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    for (final label in ['Input', 'Context', 'Tools', 'Conversation']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byKey(const Key('llm-kit-run-button')), findsNothing);
    expect(find.byKey(const Key('llm-resize-handle')), findsNothing);
    final name = tester.widget<Text>(
      find.byKey(const Key('kit-overview-name')),
    );
    expect(name.style!.fontSize, greaterThanOrEqualTo(11));

    await pumpLayer(tester, zoom: 1);
    expect(find.byKey(const Key('kit-overview-frame')), findsNothing);
    for (final label in ['Input', 'Context', 'Tools', 'Conversation']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('mid-transition, detail and overview crossfade', (tester) async {
    Future<void> at(double progress) {
      return tester.pumpWidget(
        MaterialApp(
          home: SizedBox.fromSize(
            size: viewport,
            child: SceneObjectLayer(
              camera: CanvasCamera(zoom: 0.7),
              viewportSize: viewport,
              objects: const [frame, body],
              registry: createBuiltinRegistry(),
              overviewProgress: progress,
            ),
          ),
        ),
      );
    }

    double opacityOf(Key key) => tester
        .widget<Opacity>(
          find.ancestor(of: find.byKey(key), matching: find.byType(Opacity)),
        )
        .opacity;

    await at(0.25);
    expect(find.byKey(const Key('kit-overview-frame')), findsOneWidget);
    expect(find.byKey(const Key('llm-kit-chrome')), findsOneWidget);
    expect(opacityOf(const Key('kit-overview-frame')), closeTo(0.25, 0.001));
    expect(opacityOf(const Key('llm-kit-chrome')), closeTo(0.75, 0.001));

    await at(0);
    expect(find.byKey(const Key('kit-overview-frame')), findsNothing);
    await at(1);
    expect(find.byKey(const Key('llm-kit-chrome')), findsNothing);
    expect(find.byKey(const Key('kit-overview-frame')), findsOneWidget);
  });

  testWidgets('zoomed out, other kits show a one-line status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.fromSize(
          size: viewport,
          child: SceneObjectLayer(
            camera: CanvasCamera(zoom: 0.4),
            viewportSize: viewport,
            objects: const [
              SceneObject(
                id: 'text-frame',
                type: 'box',
                x: -300,
                y: -75,
                width: 280,
                height: 120,
                props: {skapieKitProp: boardTextKitId, skapieRoleProp: 'frame'},
              ),
              SceneObject(
                id: 'text-body',
                type: 'text',
                x: -288,
                y: -35,
                width: 256,
                height: 48,
                props: {
                  skapieKitProp: boardTextKitId,
                  skapieRoleProp: 'body',
                  'content': 'Hello\nsecond',
                },
              ),
              SceneObject(
                id: 'conversation-frame',
                type: 'box',
                x: 20,
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
                x: 32,
                y: -35,
                width: 256,
                height: 48,
                props: {
                  skapieKitProp: harnessConversationKitId,
                  skapieRoleProp: 'body',
                  'content': 'User\nhi\n\nAssistant\nhello',
                  'turns': [
                    {'role': 'user', 'content': 'hi'},
                    {'role': 'assistant', 'content': 'hello'},
                  ],
                },
              ),
              SceneObject(
                id: 'repo-frame',
                type: 'box',
                x: -300,
                y: 100,
                width: 280,
                height: 64,
                props: {
                  skapieKitProp: codingRepositoryKitId,
                  skapieRoleProp: 'frame',
                  repositoryPathProp: '/Users/me/src/skapie',
                },
              ),
            ],
            registry: createBuiltinRegistry(),
          ),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('+1 Line'), findsNothing);
    expect(find.text('2 turns'), findsOneWidget);
    expect(find.text('skapie'), findsOneWidget);
    expect(find.text('In'), findsNothing);
    expect(find.text('Out'), findsNothing);
    expect(find.text('In / Out'), findsNothing);
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
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
    expect(find.text('list repo files.'), findsNothing);
  });

  testWidgets('a patch proposal kit previews content once with In and Out', (
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
                id: 'proposal-frame',
                type: 'box',
                x: -140,
                y: -75,
                width: 280,
                height: 120,
                props: {
                  skapieKitProp: codingPatchProposalKitId,
                  skapieRoleProp: 'frame',
                },
              ),
              SceneObject(
                id: 'proposal-body',
                type: 'text',
                x: -128,
                y: -35,
                width: 256,
                height: 48,
                props: {
                  skapieKitProp: codingPatchProposalKitId,
                  skapieRoleProp: 'body',
                  'content': 'No proposal yet',
                },
              ),
            ],
            registry: createBuiltinRegistry(),
          ),
        ),
      ),
    );

    expect(find.text('No proposal yet'), findsOneWidget);
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
  });
}
