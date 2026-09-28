import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/app/host_status_banner.dart';
import 'package:skapie/kit_api/host_status.dart';
import 'package:skapie/paint/paint.dart';

Widget _wrap(HostStatusLog status) {
  return MaterialApp(
    home: PaintScope(
      tokens: PaintTokens.dark(),
      child: Scaffold(body: HostStatusBanner(status: status)),
    ),
  );
}

void main() {
  testWidgets('host status banner is absent when healthy and dismisses a fault', (
    tester,
  ) async {
    final status = HostStatusLog();
    await tester.pumpWidget(_wrap(status));
    expect(find.byKey(const Key('host-status-banner')), findsNothing);

    status.report(key: 'package:demo.bad', message: 'Skip demo.bad: bad json');
    await tester.pump();
    expect(find.byKey(const Key('host-status-banner')), findsOneWidget);
    expect(find.text('Skip demo.bad: bad json'), findsOneWidget);

    await tester.tap(find.byKey(const Key('host-status-dismiss-package:demo.bad')));
    await tester.pump();
    expect(find.byKey(const Key('host-status-banner')), findsNothing);
  });
}
