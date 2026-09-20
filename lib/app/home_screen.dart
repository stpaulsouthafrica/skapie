import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/shared/app_info.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Column(
        children: [
          Material(
            color: colors.surfaceContainerHighest,
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(AppInfo.name, style: textTheme.labelLarge),
                ),
              ),
            ),
          ),
          const Expanded(child: CanvasViewport()),
        ],
      ),
    );
  }
}
