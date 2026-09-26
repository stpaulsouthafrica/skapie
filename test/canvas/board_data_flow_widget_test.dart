import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/board_data_flow.dart';
import 'package:skapie/canvas/cable_activity.dart';
import 'package:skapie/canvas/cable_layer.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/patch_board.dart';

void main() {
  testWidgets('a recorded board transfer lights the receiving kit', (
    tester,
  ) async {
    final api = createAppKitApi(store: SceneStore());
    final source = api
        .instantiate(proposePatchKitId, origin: const Offset(-350, -70))
        .first;
    final target = api
        .instantiate(codingPatchProposalKitId, origin: const Offset(-40, -70))
        .first;
    final ports = kitPorts(api.store.document);
    connectKitPorts(
      kitApi: api,
      from: ports.singleWhere(
        (port) =>
            port.frameId == source && port.kind == KitPortKind.proposalResult,
      ),
      to: ports.singleWhere(
        (port) => port.frameId == target && port.kind == KitPortKind.proposalIn,
      ),
    );
    final cable = sceneCables(api.store.document).single;
    final glow = ActivityGlow();

    Widget layer(List<BoardDataEvent> events) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 400,
          child: CableLayer(
            camera: CanvasCamera(),
            viewportSize: const Size(900, 400),
            document: api.store.document,
            boardEvents: events,
            glow: glow,
          ),
        ),
      ),
    );

    await tester.pumpWidget(layer(const []));
    expect(glow.of(target), 0);
    await tester.pumpWidget(
      layer([
        BoardDataEvent(1, BoardDataRoute([cable.id], [source, target])),
      ]),
    );
    expect(glow.of(target), 0);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await tester.pump();
    expect(glow.of(target), greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    glow.dispose();
  });

  testWidgets('Patch Proposal reveals its new preview when the cable arrives', (
    tester,
  ) async {
    final api = createAppKitApi(store: SceneStore());
    final source = api
        .instantiate(proposePatchKitId, origin: const Offset(-350, -70))
        .first;
    final target = api
        .instantiate(codingPatchProposalKitId, origin: const Offset(-40, -70))
        .first;
    final ports = kitPorts(api.store.document);
    connectKitPorts(
      kitApi: api,
      from: ports.singleWhere(
        (port) =>
            port.frameId == source && port.kind == KitPortKind.proposalResult,
      ),
      to: ports.singleWhere(
        (port) => port.frameId == target && port.kind == KitPortKind.proposalIn,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewport(store: api.store, kitApi: api),
        ),
      ),
    );
    expect(find.text('Waiting for a proposal'), findsOneWidget);

    final before = api.store.document;
    writePatchProposal(
      kitApi: api,
      proposeFrameId: source,
      proposal: {
        'proposalId': 'proposal-one',
        'path': 'file.txt',
        'diff': '--- a/file.txt\n+++ b/file.txt\n-before\n+after\n',
      },
    );
    expect(boardDataRoutesForChange(before, api.store.document), isNotEmpty);
    await tester.pump();
    expect(find.text('Waiting for a proposal'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('file.txt'), findsOneWidget);
  });
}
