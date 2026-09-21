import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/app/agent_chat_panel.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/shared/app_info.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.registry,
    required this.kitApi,
    required this.agentController,
  });

  final SceneStore store;
  final ObjectRegistry registry;
  final KitApi kitApi;
  final AgentController agentController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _viewportKey = GlobalKey<CanvasViewportState>();
  final _selection = SelectionController();
  var _chatOpen = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _selection.addListener(_onSelection);
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
    _selection.removeListener(_onSelection);
    _selection.dispose();
    super.dispose();
  }

  void _onStore() {
    _selection.syncToDocument(widget.store.document);
    setState(() {});
  }

  void _onSelection() => setState(() {});

  void _add(String value) {
    if (widget.kitApi.getKit(value) != null) {
      _viewportKey.currentState?.instantiateKit(value);
      return;
    }
    _viewportKey.currentState?.addTypedObject(value);
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
                    child: IconButton(
                      tooltip: 'Chat',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: () => setState(() => _chatOpen = !_chatOpen),
                      icon: Icon(
                        _chatOpen
                            ? Icons.chat_bubble
                            : Icons.chat_bubble_outline,
                      ),
                    ),
                  ),
                  Focus(
                    canRequestFocus: false,
                    descendantsAreFocusable: false,
                    child: PopupMenuButton<String>(
                      tooltip: 'Add scene object',
                      onSelected: _add,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: boxTypeId,
                          child: Text('Box'),
                        ),
                        const PopupMenuItem(
                          value: textTypeId,
                          child: Text('Text'),
                        ),
                        const PopupMenuItem(
                          value: buttonTypeId,
                          child: Text('Button'),
                        ),
                        const PopupMenuItem(
                          value: debugRectType,
                          child: Text('Debug rect'),
                        ),
                        for (final kit in widget.kitApi.listKits())
                          PopupMenuItem(
                            value: kit.id,
                            child: Text(
                              kit.id == demoNoteCardKitId
                                  ? 'Demo kit: note card'
                                  : 'Kit: ${kit.displayName}',
                            ),
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                CanvasViewport(
                  key: _viewportKey,
                  store: widget.store,
                  registry: widget.registry,
                  selection: _selection,
                  kitApi: widget.kitApi,
                ),
                if (_chatOpen)
                  Positioned(
                    top: 0,
                    left: 0,
                    bottom: 0,
                    child: AgentChatPanel(controller: widget.agentController),
                  ),
                if (_selection.selectedId != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: Material(
                      elevation: 6,
                      color: colors.surfaceContainerHighest,
                      shadowColor: colors.shadow,
                      child: InspectorPanel(
                        store: widget.store,
                        selection: _selection,
                        kitApi: widget.kitApi,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
