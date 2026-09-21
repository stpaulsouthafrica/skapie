import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/app/agent_settings_panel.dart';
import 'package:skapie/app/command_palette.dart';
import 'package:skapie/app/inspector_panel.dart';
import 'package:skapie/canvas/canvas_viewport.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/tools/attach.dart';

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
  var _paletteOpen = false;
  String? _lastLlmBodyId;
  String? _lastToolObjectId;

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

  void _onSelection() {
    final id = _selection.selectedId;
    if (id != null) {
      final llm = llmKitBodyForSelection(
        document: widget.store.document,
        selectedId: id,
      );
      if (llm != null) {
        _lastLlmBodyId = llm.id;
      }
      final object = widget.store.document.objectById(id);
      if (object != null && isWorldToolKit(object)) {
        _lastToolObjectId = object.id;
      }
    }
    setState(() {});
  }

  bool _isEditingText() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) {
      return false;
    }
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _openSettings() => setState(() {
    _settingsOpen = true;
    _paletteOpen = false;
  });

  void _closeSettings() => setState(() => _settingsOpen = false);

  void _openPaletteIfIdle() {
    if (_paletteOpen || _settingsOpen || _isEditingText()) {
      return;
    }
    setState(() => _paletteOpen = true);
  }

  void _closePalette() => setState(() => _paletteOpen = false);

  Offset get _placeOrigin {
    return _viewportKey.currentState?.camera.offset ?? Offset.zero;
  }

  void _add(String value) {
    if (widget.kitApi.getKit(value) != null) {
      final ids = widget.kitApi.instantiate(value, origin: _placeOrigin);
      if (value == harnessLlmKitId) {
        for (final id in ids) {
          final object = widget.store.document.objectById(id);
          if (object != null && object.props[skapieRoleProp] == 'body') {
            _lastLlmBodyId = id;
            _selection.select(id);
            break;
          }
        }
      } else if (value.startsWith('tools.')) {
        for (final id in ids) {
          final object = widget.store.document.objectById(id);
          if (object != null &&
              (object.props['toolName']?.toString().trim() ?? '').isNotEmpty) {
            _lastToolObjectId = id;
            _selection.select(id);
            break;
          }
        }
      }
      return;
    }
    _viewportKey.currentState?.addTypedObject(value);
  }

  void _attachToLlm() {
    final toolId = _lastToolObjectId;
    final llmId = _lastLlmBodyId;
    if (toolId == null || llmId == null) {
      return;
    }
    attachToolKit(
      kitApi: widget.kitApi,
      toolObjectId: toolId,
      llmBodyId: llmId,
    );
  }

  void _detachTool() {
    final toolId = _lastToolObjectId ?? _selection.selectedId;
    if (toolId == null) {
      return;
    }
    detachToolKit(kitApi: widget.kitApi, toolObjectId: toolId);
  }

  List<CommandAction> _paletteActions() {
    return [
      ...defaultCommandActions,
      for (final kit in widget.kitApi.listKits())
        if (kit.id.startsWith('tools.'))
          CommandAction(id: 'add-${kit.id}', label: 'Tool: ${kit.displayName}'),
      const CommandAction(id: 'attach-to-llm', label: 'Attach to LLM'),
      const CommandAction(id: 'detach-tool', label: 'Detach tool'),
    ];
  }

  void _runCommand(CommandAction action) {
    _closePalette();
    switch (action.id) {
      case 'settings':
        _openSettings();
      case 'add-llm':
        _add(harnessLlmKitId);
      case 'add-system-prompt':
        _add(harnessSystemPromptKitId);
      case 'add-tools':
        _add(harnessToolsKitId);
      case 'add-box':
        _add(boxTypeId);
      case 'add-text':
        _add(textTypeId);
      case 'add-button':
        _add(buttonTypeId);
      case 'add-debug-rect':
        _add(debugRectType);
      case 'add-note-card':
        _add(demoNoteCardKitId);
      case 'attach-to-llm':
        _attachToLlm();
      case 'detach-tool':
        _detachTool();
      default:
        if (action.id.startsWith('add-tools.')) {
          _add(action.id.substring(4));
        }
    }
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
                : kit.id.startsWith('tools.')
                ? 'Tool: ${kit.displayName}'
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
    final emptyWorld = widget.store.document.objects.isEmpty;
    final tokens = PaintScope.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _openSettings,
        const SingleActivator(LogicalKeyboardKey.space): _openPaletteIfIdle,
        const SingleActivator(LogicalKeyboardKey.f3): _openPaletteIfIdle,
      },
      child: Scaffold(
        body: Stack(
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
                bottom: 16,
                child: PaintPanel(
                  padding: EdgeInsets.zero,
                  child: InspectorPanel(
                    store: widget.store,
                    selection: _selection,
                    kitApi: widget.kitApi,
                    lastLlmBodyId: _lastLlmBodyId,
                    controller: widget.agentController,
                  ),
                ),
              ),
            if (emptyWorld && !_paletteOpen && !_settingsOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: IgnorePointer(
                  child: Text(
                    'Space to add',
                    key: const Key('empty-world-hint'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.muted),
                  ),
                ),
              ),
            if (_paletteOpen)
              Positioned.fill(
                child: Stack(
                  children: [
                    ModalBarrier(
                      dismissible: true,
                      color: Colors.black.withValues(alpha: 0.28),
                      onDismiss: _closePalette,
                    ),
                    Align(
                      alignment: const Alignment(0, -0.45),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 360,
                          maxHeight: 420,
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: CommandPalette(
                            key: const Key('command-palette'),
                            actions: _paletteActions(),
                            onClose: _closePalette,
                            onRun: _runCommand,
                          ),
                        ),
                      ),
                    ),
                  ],
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
        ),
      ),
    );
  }
}
