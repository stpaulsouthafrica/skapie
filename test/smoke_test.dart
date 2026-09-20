import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('home screen shows the app name', (tester) async {
    await tester.pumpWidget(SkapieApp(store: SceneStore()));

    expect(find.text('Skapie'), findsOneWidget);
  });

  testWidgets('Add menu inserts a debug.rect scene object', (tester) async {
    final store = SceneStore();
    await tester.pumpWidget(SkapieApp(store: store));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug rect'));
    await tester.pump();

    expect(store.document.objects, hasLength(1));
    expect(store.document.objects.single.type, 'debug.rect');
  });

  testWidgets('Add box, text, and button insert typed objects', (tester) async {
    final store = SceneStore();
    await tester.pumpWidget(SkapieApp(store: store));

    Future<void> add(String label) async {
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pump();
    }

    await add('Box');
    await add('Text');
    await add('Button');

    expect(store.document.objects.map((o) => o.type), [
      'box',
      'text',
      'button',
    ]);
  });

  testWidgets('header shows a short scene label, not the absolute path', (
    tester,
  ) async {
    const absolute =
        '/Users/me/Library/Containers/com.skapie.skapie/Data/Library/Application Support/com.skapie.skapie/skapie/scene.json';
    final store = SceneStore(persistence: SceneFilePersistence(File(absolute)));
    await tester.pumpWidget(SkapieApp(store: store));

    expect(find.text('Scene: App Support'), findsOneWidget);
    expect(find.textContaining(absolute), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == absolute,
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy path'), findsOneWidget);
  });
}
