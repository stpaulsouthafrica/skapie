import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:skapie/agent/conversation_kit.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/paint/paint.dart';

/// Full-screen chat view of a Conversation kit, read straight from its turns.
Future<void> showConversationKitViewer({
  required BuildContext context,
  required KitApi kitApi,
  required String bodyId,
  required String title,
}) {
  final tokens = PaintScope.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close conversation',
    barrierColor: const Color(0xE60C0C0E),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _ConversationKitViewer(
        tokens: tokens,
        kitApi: kitApi,
        bodyId: bodyId,
        title: title,
      );
    },
  );
}

class _ConversationKitViewer extends StatelessWidget {
  const _ConversationKitViewer({
    required this.tokens,
    required this.kitApi,
    required this.bodyId,
    required this.title,
  });

  final PaintTokens tokens;
  final KitApi kitApi;
  final String bodyId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('conversation-kit-viewer'),
      color: tokens.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          child: ListenableBuilder(
            listenable: kitApi.store,
            builder: (context, _) {
              final body = kitApi.store.document.objectById(bodyId);
              final turns = body == null
                  ? const <ConversationTurn>[]
                  : conversationTurnsOf(body);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, hasTurns: turns.isNotEmpty),
                  const SizedBox(height: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.panel,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.hairline),
                      ),
                      child: turns.isEmpty
                          ? Center(
                              child: Text(
                                'No turns yet',
                                style: TextStyle(color: tokens.muted),
                              ),
                            )
                          : _turnList(turns),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, {required bool hasTurns}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: tokens.ink),
          ),
        ),
        if (hasTurns)
          TextButton(
            key: const Key('conversation-kit-clear'),
            onPressed: () => clearConversation(kitApi: kitApi, bodyId: bodyId),
            child: Text('Clear', style: TextStyle(color: tokens.muted)),
          ),
        IconButton(
          key: const Key('conversation-kit-viewer-close'),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close, color: tokens.muted),
        ),
      ],
    );
  }

  Widget _turnList(List<ConversationTurn> turns) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubble = math.min(720.0, constraints.maxWidth * 0.72);
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(20),
          itemCount: turns.length,
          itemBuilder: (context, index) {
            final turn = turns[turns.length - 1 - index];
            return _bubble(turn, maxBubble);
          },
        );
      },
    );
  }

  Widget _bubble(ConversationTurn turn, double maxWidth) {
    final user = turn.role == 'user';
    final shade = user
        ? Color.alphaBlend(tokens.accent.withValues(alpha: 0.14), tokens.panel)
        : Color.alphaBlend(tokens.ink.withValues(alpha: 0.05), tokens.panel);
    final meta = [
      user ? 'User' : 'Assistant',
      if (turn.at != null) conversationTimestamp(turn.at!),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        key: Key('conversation-turn-${turn.role}'),
        crossAxisAlignment: user
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              meta,
              style: TextStyle(color: tokens.muted, fontSize: 11),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: shade,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(user ? 12 : 3),
                  bottomRight: Radius.circular(user ? 3 : 12),
                ),
                border: Border.all(
                  color: user
                      ? tokens.accent.withValues(alpha: 0.28)
                      : tokens.ink.withValues(alpha: 0.08),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: SelectableText(
                  turn.content,
                  style: TextStyle(
                    color: tokens.ink,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `20:10` today, otherwise `23 Sep 20:10`.
String conversationTimestamp(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  if (sameDay) {
    return time;
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${local.day} ${months[local.month - 1]}';
  return local.year == today.year ? '$date $time' : '$date ${local.year} $time';
}
