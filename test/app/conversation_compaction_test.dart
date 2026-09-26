import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/app/conversation_kit_viewer.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  testWidgets('Compact turns the oldest turns into a summary card', (
    tester,
  ) async {
    final store = SceneStore();
    final api = createAppKitApi(store: store);
    final conversation = api.instantiate(
      harnessConversationKitId,
      origin: Offset.zero,
    );
    api.updateProps(conversation.last, {
      'turns': [
        {'role': 'user', 'content': 'first ask'},
        {'role': 'assistant', 'content': 'first answer'},
        {'role': 'user', 'content': 'second ask'},
        {'role': 'assistant', 'content': 'second answer'},
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showConversationKitViewer(
                  context: context,
                  kitApi: api,
                  bodyId: conversation.last,
                  title: 'Conversation',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('conversation-kit-compact')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-compaction')), findsOneWidget);
    expect(
      conversationTurnsOf(store.document.objectById(conversation.last)!),
      hasLength(4),
    );

    await tester.tap(find.byKey(const Key('conversation-kit-restore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation-compaction')), findsNothing);
  });
}
