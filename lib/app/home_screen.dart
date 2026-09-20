import 'package:flutter/material.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/scene/scene_store.dart';
import 'package:skapie/shared/app_info.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final SceneStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _viewportKey = GlobalKey<CanvasViewportState>();

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
                child: Row(
                  children: [
                    Text(AppInfo.name, style: textTheme.labelLarge),
                    const Spacer(),
                    Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            _viewportKey.currentState?.addDebugRect(),
                        child: const Text('Add debug rect'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: CanvasViewport(key: _viewportKey, store: widget.store),
          ),
        ],
      ),
    );
  }
}
