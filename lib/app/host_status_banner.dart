import 'package:flutter/material.dart';
import 'package:skapie/kit_api/host_status.dart';
import 'package:skapie/paint/paint.dart';

/// Top-left host status. Shows package load faults and grant/tool denials only
/// while there is something to say. The user can dismiss each note.
class HostStatusBanner extends StatelessWidget {
  const HostStatusBanner({super.key, required this.status});

  final HostStatusLog status;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final items = status.items;
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        final tokens = PaintScope.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              key: const Key('host-status-banner'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.panel,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: item.isError
                              ? tokens.danger.withValues(alpha: 0.5)
                              : tokens.hairline,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.message,
                                key: Key('host-status-row-${item.key}'),
                                style: TextStyle(
                                  color: item.isError
                                      ? tokens.danger
                                      : tokens.ink,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            PaintIconButton(
                              key: Key('host-status-dismiss-${item.key}'),
                              tooltip: 'Dismiss',
                              icon: Icons.close,
                              onPressed: () => status.clear(item.key),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
