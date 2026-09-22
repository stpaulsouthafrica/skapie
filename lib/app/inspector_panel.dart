import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/agent_controller.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/app/llm_kit_input.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

/// Thin inspector. Edits go through [KitApi] → [SceneStore.apply] only.
class InspectorPanel extends StatefulWidget {
  InspectorPanel({
    super.key,
    required this.store,
    required this.selection,
    KitApi? kitApi,
    this.lastLlmBodyId,
    this.controller,
  }) : kitApi =
           kitApi ?? KitApi(store: store, registry: createBuiltinRegistry());

  final SceneStore store;
  final SelectionController selection;
  final KitApi kitApi;
  final String? lastLlmBodyId;
  final AgentController? controller;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  Timer? _debounce;
  String? _boundId;
  final _x = TextEditingController();
  final _y = TextEditingController();
  final _content = TextEditingController();
  final _contentFocus = FocusNode();
  final _fontSize = TextEditingController();
  final _color = TextEditingController();
  final _fill = TextEditingController();
  final _label = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    widget.selection.addListener(_onSelection);
    _contentFocus.addListener(_onContentFocus);
    _bindObject(force: true);
  }

  @override
  void didUpdateWidget(InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
    }
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelection);
      widget.selection.addListener(_onSelection);
    }
    _bindObject(force: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.store.removeListener(_onStore);
    widget.selection.removeListener(_onSelection);
    _contentFocus.removeListener(_onContentFocus);
    _x.dispose();
    _y.dispose();
    _content.dispose();
    _contentFocus.dispose();
    _fontSize.dispose();
    _color.dispose();
    _fill.dispose();
    _label.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onStore() {
    widget.selection.syncToDocument(widget.store.document);
    if (_debounce?.isActive ?? false) {
      setState(() {});
      return;
    }
    _bindObject(force: false);
    setState(() {});
  }

  void _onSelection() {
    _bindObject(force: true);
    setState(() {});
  }

  void _onContentFocus() {
    if (_contentFocus.hasFocus) {
      return;
    }
    _bindObject(force: true);
    setState(() {});
  }

  SceneObject? get _object {
    final id = widget.selection.selectedId;
    if (id == null) {
      return null;
    }
    return widget.store.document.objectById(id);
  }

  SceneObject? get _frame {
    final object = _object;
    if (object == null) {
      return null;
    }
    return kitFrameForSelection(
          document: widget.store.document,
          selectedId: object.id,
        ) ??
        object;
  }

  void _bindObject({required bool force}) {
    final object = _object;
    final frame = _frame;
    if (object == null || frame == null) {
      _boundId = null;
      return;
    }
    final idChanged = _boundId != object.id;
    final fill = kitHasCustomFill(frame)
        ? _string(frame.props, 'fill')
        : colorToHex(PaintTokens.dark().panel);
    if (!force && !idChanged) {
      _syncField(
        _content,
        _string(object.props, 'content'),
        skip: _contentFocus.hasFocus,
      );
      _syncField(_x, _fmt(frame.x));
      _syncField(_y, _fmt(frame.y));
      _syncField(_fontSize, _string(object.props, 'fontSize'));
      _syncField(_color, _string(object.props, 'color'));
      _syncField(_fill, fill);
      _syncField(_label, _string(object.props, 'label'));
      _syncField(
        _name,
        kitDisplayName(widget.store.document, frame),
        skip: _nameFocus.hasFocus,
      );
      return;
    }
    _boundId = object.id;
    _syncField(_x, _fmt(frame.x));
    _syncField(_y, _fmt(frame.y));
    _syncField(
      _content,
      _string(object.props, 'content'),
      skip: !idChanged && _contentFocus.hasFocus,
    );
    _syncField(_fontSize, _string(object.props, 'fontSize'));
    _syncField(_color, _string(object.props, 'color'));
    _syncField(_fill, fill);
    _syncField(_label, _string(object.props, 'label'));
    _syncField(
      _name,
      kitDisplayName(widget.store.document, frame),
      skip: !idChanged && _nameFocus.hasFocus,
    );
  }

  void _syncField(
    TextEditingController controller,
    String value, {
    bool skip = false,
  }) {
    if (skip) {
      return;
    }
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String _fmt(double value) {
    final rounded = (value * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toString();
  }

  String _string(Map<String, Object?> props, String key) {
    final value = props[key];
    return value == null ? '' : '$value';
  }

  void _applyProps(
    Map<String, Object?> patch, {
    bool immediate = false,
    String? id,
  }) {
    final target = id ?? widget.selection.selectedId;
    if (target == null) {
      return;
    }
    void commit() {
      widget.kitApi.updateProps(target, patch);
    }

    _debounce?.cancel();
    if (immediate) {
      commit();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), commit);
  }

  void _applyAppearance(Map<String, Object?> patch, {bool immediate = false}) {
    final frame = _frame;
    if (frame == null) {
      return;
    }
    _applyProps(patch, immediate: immediate, id: frame.id);
  }

  void _rename(String value, {bool immediate = false}) {
    final frame = _frame;
    final name = value.trim();
    if (frame == null || name.isEmpty || !isKitObject(frame)) {
      return;
    }
    final members =
        kitMembers(document: widget.store.document, selectedId: frame.id) ??
        [frame];
    void commit() {
      for (final member in members) {
        widget.kitApi.updateProps(member.id, {kitNameProp: name});
      }
    }

    _debounce?.cancel();
    if (immediate) {
      commit();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), commit);
  }

  void _applyFrame({double? x, double? y}) {
    final frame = _frame;
    if (frame == null) {
      return;
    }
    final members =
        kitMembers(document: widget.store.document, selectedId: frame.id) ??
        [frame];
    final dx = x == null ? 0.0 : x - frame.x;
    final dy = y == null ? 0.0 : y - frame.y;
    if (dx == 0 && dy == 0) {
      return;
    }
    for (final member in members) {
      widget.kitApi.updateFrame(
        id: member.id,
        x: x == null ? null : member.x + dx,
        y: y == null ? null : member.y + dy,
      );
    }
  }

  void _delete() {
    final id = widget.selection.selectedId;
    if (id == null) {
      return;
    }
    removeKitSelection(kitApi: widget.kitApi, selectedId: id);
    widget.selection.syncToDocument(widget.store.document);
  }

  @override
  Widget build(BuildContext context) {
    final object = _object;
    final frame = _frame;
    if (object == null || frame == null) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    final llmBody = llmKitBodyForSelection(
      document: widget.store.document,
      selectedId: object.id,
    );
    final controller = widget.controller;
    final typeLabel = llmBody != null
        ? 'LLM'
        : isWorldToolKit(object)
        ? kitNameStem(kitIdOf(object)!)
        : object.type;

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Inspector', style: textTheme.labelLarge),
                    _section('Type', [
                      _readOnly('', typeLabel, hideLabel: true),
                    ]),
                    _section('Identity', [
                      if (isKitObject(object))
                        _field(
                          key: const Key('inspector-id'),
                          label: 'Id',
                          controller: _name,
                          focusNode: _nameFocus,
                          onChanged: _rename,
                          onSubmitted: (value) =>
                              _rename(value, immediate: true),
                        )
                      else
                        _readOnly('Id', object.id),
                    ]),
                    _section('Transform', [
                      PaintHover(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Locked'),
                          subtitle: const Text('Select and delete ok, no move'),
                          value: object.locked,
                          onChanged: (value) {
                            widget.kitApi.setLocked(object.id, value);
                          },
                        ),
                      ),
                      _field(
                        label: 'X',
                        controller: _x,
                        onSubmitted: (value) {
                          final parsed = double.tryParse(value);
                          if (parsed != null) {
                            _applyFrame(x: parsed);
                          }
                        },
                      ),
                      _field(
                        label: 'Y',
                        controller: _y,
                        onSubmitted: (value) {
                          final parsed = double.tryParse(value);
                          if (parsed != null) {
                            _applyFrame(y: parsed);
                          }
                        },
                      ),
                    ]),
                    if (frame.type == boxTypeId || isKitObject(object))
                      _section('Appearance', [
                        if (isKitObject(object))
                          _swatches(frame)
                        else
                          _field(
                            key: const Key('inspector-fill'),
                            label: 'Fill',
                            controller: _fill,
                            onChanged: (value) =>
                                _applyAppearance({'fill': value}),
                            onSubmitted: (value) => _applyAppearance({
                              'fill': value,
                            }, immediate: true),
                          ),
                      ]),
                    if (llmBody != null && controller != null)
                      _section('Model / IO', [
                        LlmKitInput(
                          body: llmBody,
                          kitApi: widget.kitApi,
                          controller: controller,
                        ),
                      ]),
                    if (llmBody == null &&
                        object.type != boxTypeId &&
                        !isWorldToolKit(object))
                      _section('Content', _typeFields(object)),
                    if (llmBody != null)
                      _section('Tools', [
                        _readOnly('Attached', () {
                          final names = attachedToolNames(
                            kitApi: widget.kitApi,
                            llmBodyId: llmBody.id,
                          );
                          return names.isEmpty ? 'none' : names.join(', ');
                        }()),
                      ]),
                    if (isWorldToolKit(object) ||
                        kitIdOf(object) == boardTextKitId)
                      _section(
                        'Allowed connections',
                        _allowedConnections(object),
                      ),
                    if (llmBody != null)
                      _section(
                        'Allowed connections',
                        _llmAllowedConnections(llmBody),
                      ),
                    const SizedBox(height: PaintTokens.space),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: _section('Actions', [
                PaintButton(label: 'Delete', onPressed: _delete),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatches(SceneObject frame) {
    final tokens = PaintScope.of(context);
    final selected = colorToHex(kitAccentColor(frame));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        key: const Key('kit-swatches'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final swatch in kitSwatches)
            GestureDetector(
              key: ValueKey('kit-swatch-${colorToHex(swatch)}'),
              onTap: () {
                _applyAppearance({
                  kitAccentProp: colorToHex(swatch),
                }, immediate: true);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorToHex(swatch) == selected
                        ? tokens.ink
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 18, height: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _allowedConnections(SceneObject object) {
    final bodies = llmBodies(widget.store.document);
    if (bodies.isEmpty) {
      return [_readOnly('', 'None on the board', hideLabel: true)];
    }
    if (isWorldToolKit(object)) {
      final current = object.props[attachedToProp]?.toString().trim() ?? '';
      return [
        for (final body in bodies)
          _connectionRow(
            kit: body,
            connected: current.isNotEmpty && current == body.id,
            onTap: () {
              if (current == body.id) {
                detachToolKit(kitApi: widget.kitApi, toolObjectId: object.id);
              } else {
                attachToolKit(
                  kitApi: widget.kitApi,
                  toolObjectId: object.id,
                  llmBodyId: body.id,
                );
              }
            },
          ),
      ];
    }
    final frame = _frame ?? object;
    final current = textConnectedLlmId(frame);
    final port = textConnectedPort(frame);
    return [
      for (final body in bodies) ...[
        _connectionRow(
          kit: body,
          detail: 'Input',
          keyId: 'input-${body.id}',
          connected: current == body.id && port == llmInputPort,
          onTap: () => _toggleText(
            objectId: object.id,
            bodyId: body.id,
            port: llmInputPort,
            current: current,
            currentPort: port,
          ),
        ),
        _connectionRow(
          kit: body,
          detail: 'Context',
          keyId: 'context-${body.id}',
          connected: current == body.id && port == llmContextPort,
          onTap: () => _toggleText(
            objectId: object.id,
            bodyId: body.id,
            port: llmContextPort,
            current: current,
            currentPort: port,
          ),
        ),
      ],
    ];
  }

  void _toggleText({
    required String objectId,
    required String bodyId,
    required String port,
    required String current,
    required String currentPort,
  }) {
    if (current == bodyId && currentPort == port) {
      disconnectText(kitApi: widget.kitApi, textObjectId: objectId);
      return;
    }
    connectTextToLlm(
      kitApi: widget.kitApi,
      textObjectId: objectId,
      llmBodyId: bodyId,
      port: port,
    );
  }

  List<Widget> _llmAllowedConnections(SceneObject body) {
    final document = widget.store.document;
    final texts = textFrames(document);
    final tools = toolFrames(document);
    final others = [
      for (final other in llmBodies(document))
        if (other.id != body.id) other,
    ];
    final outputTarget = body.props[outputToProp]?.toString().trim() ?? '';
    final outputPort =
        (body.props[outputPortProp]?.toString().trim() ?? '') == llmContextPort
        ? llmContextPort
        : llmInputPort;
    return [
      _portHeading('Input'),
      ..._textPortRows(body, texts, llmInputPort),
      _portHeading('Context'),
      ..._textPortRows(body, texts, llmContextPort),
      _portHeading('Tools'),
      if (tools.isEmpty)
        _readOnly('', 'None on the board', hideLabel: true)
      else
        for (final tool in tools)
          _connectionRow(
            kit: tool,
            keyId: 'tools-${tool.id}',
            connected:
                (tool.props[attachedToProp]?.toString().trim() ?? '') ==
                body.id,
            onTap: () {
              final attached =
                  tool.props[attachedToProp]?.toString().trim() ?? '';
              if (attached == body.id) {
                detachToolKit(kitApi: widget.kitApi, toolObjectId: tool.id);
              } else {
                attachToolKit(
                  kitApi: widget.kitApi,
                  toolObjectId: tool.id,
                  llmBodyId: body.id,
                );
              }
            },
          ),
      _portHeading('Output'),
      if (others.isEmpty)
        _readOnly('', 'None on the board', hideLabel: true)
      else
        for (final other in others) ...[
          _connectionRow(
            kit: other,
            detail: 'Input',
            keyId: 'output-input-${other.id}',
            connected: outputTarget == other.id && outputPort == llmInputPort,
            onTap: () => _toggleOutput(
              sourceId: body.id,
              targetId: other.id,
              port: llmInputPort,
              current: outputTarget,
              currentPort: outputPort,
            ),
          ),
          _connectionRow(
            kit: other,
            detail: 'Context',
            keyId: 'output-context-${other.id}',
            connected: outputTarget == other.id && outputPort == llmContextPort,
            onTap: () => _toggleOutput(
              sourceId: body.id,
              targetId: other.id,
              port: llmContextPort,
              current: outputTarget,
              currentPort: outputPort,
            ),
          ),
        ],
    ];
  }

  List<Widget> _textPortRows(
    SceneObject body,
    List<SceneObject> texts,
    String port,
  ) {
    if (texts.isEmpty) {
      return [_readOnly('', 'None on the board', hideLabel: true)];
    }
    return [
      for (final text in texts)
        _connectionRow(
          kit: text,
          keyId: '$port-${text.id}',
          connected:
              textConnectedLlmId(text) == body.id &&
              textConnectedPort(text) == port,
          onTap: () => _toggleText(
            objectId: text.id,
            bodyId: body.id,
            port: port,
            current: textConnectedLlmId(text),
            currentPort: textConnectedPort(text),
          ),
        ),
    ];
  }

  void _toggleOutput({
    required String sourceId,
    required String targetId,
    required String port,
    required String current,
    required String currentPort,
  }) {
    if (current == targetId && currentPort == port) {
      disconnectLlmOutput(kitApi: widget.kitApi, sourceBodyId: sourceId);
      return;
    }
    connectLlmOutput(
      kitApi: widget.kitApi,
      sourceBodyId: sourceId,
      targetBodyId: targetId,
      port: port,
    );
  }

  Widget _portHeading(String label) {
    final tokens = PaintScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: tokens.muted, letterSpacing: 0.3),
      ),
    );
  }

  Widget _connectionRow({
    required SceneObject kit,
    required bool connected,
    required VoidCallback onTap,
    String? keyId,
    String? detail,
  }) {
    final tokens = PaintScope.of(context);
    final frame =
        kitFrameForSelection(
          document: widget.store.document,
          selectedId: kit.id,
        ) ??
        kit;
    final name = kitDisplayName(widget.store.document, kit);
    final color = kitAccentColor(frame);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PaintHover(
        child: GestureDetector(
          key: ValueKey('allowed-connection-${keyId ?? kit.id}'),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PaintTokens.radiusField),
              border: Border.all(
                color: connected ? color : tokens.hairline,
                width: connected ? 1.4 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (detail != null) ...[
                    Text(
                      detail,
                      style: TextStyle(color: tokens.muted, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (connected)
                    Text(
                      'Connected',
                      style: TextStyle(color: tokens.muted, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final tokens = PaintScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(color: tokens.hairline, child: const SizedBox(height: 1)),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: tokens.muted, letterSpacing: 0.4),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _typeFields(SceneObject object) {
    switch (object.type) {
      case boxTypeId:
        return [
          _field(
            key: const Key('inspector-fill'),
            label: 'Fill',
            controller: _fill,
            onChanged: (value) => _applyAppearance({'fill': value}),
            onSubmitted: (value) =>
                _applyAppearance({'fill': value}, immediate: true),
          ),
        ];
      case textTypeId:
        return [
          _field(
            key: const Key('inspector-content'),
            label: 'Content',
            controller: _content,
            focusNode: _contentFocus,
            onChanged: (value) => _applyProps({'content': value}),
            onSubmitted: (value) =>
                _applyProps({'content': value}, immediate: true),
          ),
          _field(
            label: 'Font size',
            controller: _fontSize,
            onSubmitted: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) {
                _applyProps({'fontSize': parsed}, immediate: true);
              }
            },
          ),
          _field(
            label: 'Color',
            controller: _color,
            onChanged: (value) => _applyProps({'color': value}),
            onSubmitted: (value) =>
                _applyProps({'color': value}, immediate: true),
          ),
        ];
      case buttonTypeId:
        return [
          _field(
            label: 'Label',
            controller: _label,
            onChanged: (value) => _applyProps({'label': value}),
            onSubmitted: (value) =>
                _applyProps({'label': value}, immediate: true),
          ),
        ];
      default:
        if (object.props.isEmpty) {
          return const [];
        }
        return [
          Text('Props', style: Theme.of(context).textTheme.labelSmall),
          for (final entry in object.props.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.key}: ${entry.value}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ];
    }
  }

  Widget _readOnly(
    String label,
    String value, {
    bool mono = false,
    bool hideLabel = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideLabel && label.isNotEmpty)
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono
                ? Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace')
                : Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _field({
    Key? key,
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PaintTextField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        label: label,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}
