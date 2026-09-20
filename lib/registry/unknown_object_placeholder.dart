import 'package:flutter/material.dart';

/// Shown when a type is unknown or a builder throws. Never evaluates Dart.
class UnknownObjectPlaceholder extends StatelessWidget {
  const UnknownObjectPlaceholder({super.key, required this.typeId});

  final String typeId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outline),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            typeId,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}
