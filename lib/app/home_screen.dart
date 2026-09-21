import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/app/agent_chat_panel.dart';
import 'package:skapie/app/agent_settings_panel.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/paint/paint.dart';

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
  var _settingsOpen = false;

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

  void _openSettings() => setState(() => _settingsOpen = true);

  void _closeSettings() => setState(() => _settingsOpen = false);

  void _add(String value) {
    if (widget.kitApi.getKit(value) != null) {
      _viewportKey.currentState?.instantiateKit(value);
      return;
    }
    _viewportKey.currentState?.addTypedObject(value);
  }

  List<PopupMenuEntry<String>> _addMenuItems(BuildContext context) {
    return [
      const PopupMenuItem(value: boxTypeId, child: Text('Box')),
      const PopupMenuItem(value: textTypeId, child: Text('Text')),
      const PopupMenuItem(value: buttonTypeId, child: Text('Button')),
      const PopupMenuItem(value: debugRectType, child: Text('Debug rect')),
      for (final kit in widget.kitApi.listKits())
        PopupMenuItem(
          value: kit.id,
          child: Text(
            kit.id == demoNoteCardKitId
                ? 'Demo kit: note card'
                : kit.id.startsWith('harness.')
                ? 'Harness: ${kit.displayName}'
                : 'Kit: ${kit.displayName}',
          ),
        ),
    ];
  }

  Widget _settingsChrome(String? label) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (label != null)
            Expanded(child: _sceneLine(label))
          else
            const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Add scene object',
            onSelected: _add,
            itemBuilder: _addMenuItems,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Add',
                style: textTheme.labelLarge?.copyWith(color: colors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sceneLine(String label) {
    final path = widget.store.sceneFilePath!;
    final saveError = widget.store.lastPersistenceError;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: saveError == null
                ? path
                : 'Save failed: $saveError\n$path',
            child: Text(
              saveError == null ? 'Scene: $label' : 'Scene save failed: $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: saveError == null
                    ? colors.onSurfaceVariant
                    : colors.error,
              ),
            ),
          ),
        ),
        PaintIconButton(
          tooltip: 'Copy path',
          icon: Icons.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: path));
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.store.sceneFilePath;
    final label = path == null ? null : scenePathLabel(path);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _OpenSettingsIntent(),
      },
      child: Actions(
        actions: {
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) {
              _openSettings();
              return null;
            },
          ),
        },
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final stripWidth = (constraints.maxWidth / 3).clamp(220.0, 420.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  CanvasViewport(
                    key: _viewportKey,
                    store: widget.store,
                    registry: widget.registry,
                    selection: _selection,
                    kitApi: widget.kitApi,
                  ),
                  if (_selection.selectedId != null)
                    Positioned(
                      top: 16,
                      right: 16,
                      bottom: constraints.maxHeight / 3,
                      child: PaintPanel(
                        padding: EdgeInsets.zero,
                        child: InspectorPanel(
                          store: widget.store,
                          selection: _selection,
                          kitApi: widget.kitApi,
                        ),
                      ),
                    ),
                  Positioned(
                    left: (constraints.maxWidth - stripWidth) / 2,
                    width: stripWidth,
                    bottom: 16,
                    child: AgentChatPanel(
                      controller: widget.agentController,
                      onOpenSettings: _openSettings,
                    ),
                  ),
                  if (_settingsOpen)
                    Positioned.fill(
                      child: Stack(
                        children: [
                          ModalBarrier(
                            dismissible: true,
                            color: Colors.black.withValues(alpha: 0.28),
                            onDismiss: _closeSettings,
                          ),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 360,
                                maxHeight: 520,
                              ),
                              child: PaintPanel(
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    _settingsChrome(label),
                                    AgentSettingsPanel(
                                      controller: widget.agentController,
                                      onClose: _closeSettings,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}
