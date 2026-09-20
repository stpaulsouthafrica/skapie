import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/scene/scene_store.dart';

void main() {
  testWidgets('home screen shows the app name', (tester) async {
    await tester.pumpWidget(SkapieApp(store: SceneStore()));

    expect(find.text('Skapie'), findsOneWidget);
  });

  testWidgets('Add debug rect inserts a scene object', (tester) async {
    final store = SceneStore();
    await tester.pumpWidget(SkapieApp(store: store));

    await tester.tap(find.text('Add debug rect'));
    await tester.pump();

    expect(store.document.objects, hasLength(1));
    expect(store.document.objects.single.type, 'debug.rect');
  });
}
