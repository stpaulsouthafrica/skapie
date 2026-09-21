import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/scene/scene.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
  await tester.sendKeyEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
  await tester.pump();
}

void main() {
  testWidgets('Cmd+, opens a transient sheet and does not resize canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = SceneStore();
    await tester.pumpWidget(SkapieApp(store: store));
    final before = tester.getSize(find.byType(CanvasViewport));

    await openSettings(tester);

    expect(find.text('Agent settings'), findsOneWidget);
    expect(find.text('Look'), findsNothing);
    expect(tester.getSize(find.byType(CanvasViewport)), before);
    expect(find.byKey(const Key('agent-chat-input')), findsNothing);
  });
}
