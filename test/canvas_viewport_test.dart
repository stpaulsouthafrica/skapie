import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/scene/scene_store.dart';

void main() {
  testWidgets('viewport fills and shows zoom hud at 100%', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CanvasViewport(store: SceneStore())),
      ),
    );

    expect(find.byType(CanvasViewport), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('mouse wheel zooms toward the pointer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CanvasViewport(store: SceneStore())),
      ),
    );

    final center = tester.getCenter(find.byType(CanvasViewport));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -240)),
    );
    await tester.pump();

    expect(find.text('200%'), findsOneWidget);
  });
}
