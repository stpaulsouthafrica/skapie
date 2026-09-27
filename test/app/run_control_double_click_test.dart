import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('double-clicking Run Control selects its inspector', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = SceneStore();
    final api = createAppKitApi(includeDemotedKits: true, store: store);
    final ids = api.instantiate(harnessRunControlKitId, origin: Offset.zero);
    await tester.pumpWidget(SkapieApp(store: store, kitApi: api));
    final kit = find.byKey(ValueKey('kit-card-${ids.first}'));
    expect(kit, findsOneWidget);
    final point = tester.getCenter(kit);

    await tester.tapAt(point);
    await tester.tapAt(point);
    await tester.pump();

    expect(find.text('Run Control'), findsWidgets);
    expect(
      find.byKey(const ValueKey('run-control-modelTurns-8')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('full-screen-text-editor')), findsNothing);
  });
}
