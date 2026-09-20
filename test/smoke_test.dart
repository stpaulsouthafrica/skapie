import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/skapie_app.dart';

void main() {
  testWidgets('home screen shows the app name', (tester) async {
    await tester.pumpWidget(const SkapieApp());

    expect(find.text('Skapie'), findsOneWidget);
  });
}
