import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/shared/app_info.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.registry});

  final SceneStore store;
  final ObjectRegistry registry;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _viewportKey = GlobalKey<CanvasViewportState>();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() => setState(() {});

  void _add(String typeId) {
    _viewportKey.currentState?.addTypedObject(typeId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final path = widget.store.sceneFilePath;
    final label = path == null ? null : scenePathLabel(path);
    final saveError = widget.store.lastPersistenceError;

    return Scaffold(
      body: Column(
        children: [
          Material(
            color: colors.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  Text(AppInfo.name, style: textTheme.labelLarge),
                  if (label != null) ...[
                    const SizedBox(width: 12),
                    Tooltip(
                      message: saveError == null
                          ? path!
                          : 'Save failed: $saveError\n$path',
                      child: Text(
                        saveError == null
                            ? 'Scene: $label'
                            : 'Scene save failed — $label',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: saveError == null
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                    ),
                    Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: IconButton(
                        tooltip: 'Copy path',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: path!));
                        },
                        icon: const Icon(Icons.copy),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Focus(
                    canRequestFocus: false,
                    descendantsAreFocusable: false,
                    child: PopupMenuButton<String>(
                      tooltip: 'Add scene object',
                      onSelected: _add,
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: boxTypeId, child: Text('Box')),
                        PopupMenuItem(value: textTypeId, child: Text('Text')),
                        PopupMenuItem(
                          value: buttonTypeId,
                          child: Text('Button'),
                        ),
                        PopupMenuItem(
                          value: debugRectType,
                          child: Text('Debug rect'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'Add',
                          style: textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: CanvasViewport(
              key: _viewportKey,
              store: widget.store,
              registry: widget.registry,
            ),
          ),
        ],
      ),
    );
  }
}
