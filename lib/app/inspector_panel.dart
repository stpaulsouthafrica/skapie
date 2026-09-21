import 'dart:async';

import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/selection_controller.dart';
import 'package:skapie/kit_api/kit_api.dart';
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
  }) : kitApi =
           kitApi ?? KitApi(store: store, registry: createBuiltinRegistry());

  final SceneStore store;
  final SelectionController selection;
  final KitApi kitApi;
  final String? lastLlmBodyId;

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
  final _cornerRadius = TextEditingController();
  final _opacity = TextEditingController();
  final _label = TextEditingController();

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
    _cornerRadius.dispose();
    _opacity.dispose();
    _label.dispose();
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

  void _bindObject({required bool force}) {
    final object = _object;
    if (object == null) {
      _boundId = null;
      return;
    }
    final idChanged = _boundId != object.id;
    if (!force && !idChanged) {
      _syncField(
        _content,
        _string(object.props, 'content'),
        skip: _contentFocus.hasFocus,
      );
      _syncField(_x, _fmt(object.x));
      _syncField(_y, _fmt(object.y));
      _syncField(_fontSize, _string(object.props, 'fontSize'));
      _syncField(_color, _string(object.props, 'color'));
      _syncField(_fill, _string(object.props, 'fill'));
      _syncField(_cornerRadius, _string(object.props, 'cornerRadius'));
      _syncField(_opacity, _string(object.props, 'opacity'));
      _syncField(_label, _string(object.props, 'label'));
      return;
    }
    _boundId = object.id;
    _syncField(_x, _fmt(object.x));
    _syncField(_y, _fmt(object.y));
    _syncField(
      _content,
      _string(object.props, 'content'),
      skip: !idChanged && _contentFocus.hasFocus,
    );
    _syncField(_fontSize, _string(object.props, 'fontSize'));
    _syncField(_color, _string(object.props, 'color'));
    _syncField(_fill, _string(object.props, 'fill'));
    _syncField(_cornerRadius, _string(object.props, 'cornerRadius'));
    _syncField(_opacity, _string(object.props, 'opacity'));
    _syncField(_label, _string(object.props, 'label'));
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
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  String _string(Map<String, Object?> props, String key) {
    final value = props[key];
    return value == null ? '' : '$value';
  }

  void _applyProps(Map<String, Object?> patch, {bool immediate = false}) {
    final id = widget.selection.selectedId;
    if (id == null) {
      return;
    }
    void commit() {
      widget.kitApi.updateProps(id, patch);
    }

    _debounce?.cancel();
    if (immediate) {
      commit();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), commit);
  }

  void _applyFrame({double? x, double? y}) {
    final id = widget.selection.selectedId;
    if (id == null) {
      return;
    }
    widget.kitApi.updateFrame(id: id, x: x, y: y);
  }

  void _delete() {
    final id = widget.selection.selectedId;
    if (id == null) {
      return;
    }
    widget.kitApi.removeObject(id);
    widget.selection.syncToDocument(widget.store.document);
  }

  @override
  Widget build(BuildContext context) {
    final object = _object;
    if (object == null) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 260,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Text('Inspector', style: textTheme.labelLarge),
            const SizedBox(height: 12),
            _readOnly('Type', object.type),
            _readOnly('Id', object.id, mono: true),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Locked'),
              subtitle: const Text('Select and delete ok, no move'),
              value: object.locked,
              onChanged: (value) {
                widget.kitApi.setLocked(object.id, value);
              },
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
            ..._typeFields(object),
            if (isLlmKitObject(object))
              _readOnly('Tools', () {
                final names = attachedToolNames(
                  kitApi: widget.kitApi,
                  llmBodyId:
                      llmKitBodyForSelection(
                        document: widget.store.document,
                        selectedId: object.id,
                      )?.id ??
                      object.id,
                );
                return names.isEmpty ? 'none' : names.join(', ');
              }()),
            if (isWorldToolKit(object)) ...[
              _readOnly(
                'Attached to',
                (object.props[attachedToProp]?.toString().trim().isNotEmpty ??
                        false)
                    ? object.props[attachedToProp].toString()
                    : 'none',
              ),
              if (widget.lastLlmBodyId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PaintButton(
                    label: 'Attach to LLM',
                    onPressed: () {
                      attachToolKit(
                        kitApi: widget.kitApi,
                        toolObjectId: object.id,
                        llmBodyId: widget.lastLlmBodyId!,
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PaintButton(
                  label: 'Detach tool',
                  onPressed: () {
                    detachToolKit(
                      kitApi: widget.kitApi,
                      toolObjectId: object.id,
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            PaintButton(label: 'Delete', onPressed: _delete),
          ],
        ),
      ),
    );
  }

  List<Widget> _typeFields(SceneObject object) {
    switch (object.type) {
      case boxTypeId:
        return [
          _field(
            label: 'Fill',
            controller: _fill,
            onChanged: (value) => _applyProps({'fill': value}),
            onSubmitted: (value) =>
                _applyProps({'fill': value}, immediate: true),
          ),
          _field(
            label: 'Corner radius',
            controller: _cornerRadius,
            onSubmitted: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) {
                _applyProps({'cornerRadius': parsed}, immediate: true);
              }
            },
          ),
          _field(
            label: 'Opacity',
            controller: _opacity,
            onSubmitted: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) {
                _applyProps({'opacity': parsed}, immediate: true);
              }
            },
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

  Widget _readOnly(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
