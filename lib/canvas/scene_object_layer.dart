import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/kit_icon.dart';
import 'package:skapie/paint/paint.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';

/// Places registered scene objects in world space. Does not mutate the scene.
class SceneObjectLayer extends StatelessWidget {
  const SceneObjectLayer({
    super.key,
    required this.camera,
    required this.viewportSize,
    required this.objects,
    required this.registry,
    this.selectedId,
    this.previewDelta = Offset.zero,
    this.previewIds = const {},
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final List<SceneObject> objects;
  final ObjectRegistry registry;
  final String? selectedId;
  final Offset previewDelta;
  final Set<String> previewIds;

  @override
  Widget build(BuildContext context) {
    if (viewportSize.isEmpty) {
      return const SizedBox.expand();
    }
    final ordered = [
      for (final object in objects)
        if (object.visible) object,
    ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [for (final object in ordered) _placed(context, object)],
      ),
    );
  }

  Widget _placed(BuildContext context, SceneObject object) {
    final preview = previewIds.contains(object.id) || object.id == selectedId
        ? previewDelta
        : Offset.zero;
    final topLeft = worldToScreen(
      Offset(object.x + preview.dx, object.y + preview.dy),
      viewportSize,
      camera,
    );
    final ctx = RegistryBuildContext(zoom: camera.zoom);
    final role = object.props[skapieRoleProp];
    final isLlmBody = isLlmKitObject(object) && role == 'body';
    final hide = isLlmBody || role == 'grant';
    Widget child = SizedBox(
      width: object.width * camera.zoom,
      height: object.height * camera.zoom,
      child: hide
          ? const SizedBox.expand()
          : registry.build(context, object, ctx: ctx),
    );
    if (role == 'frame' && isLlmKitObject(object)) {
      child = _llmChrome(context, object, child);
    } else if (role == 'frame' &&
        (kitIdOf(object)?.startsWith('tools.') ?? false)) {
      child = _toolChrome(context, object, child);
    } else if (role == 'frame' && isKitObject(object)) {
      child = _namedChrome(context, object, child);
    }
    if (role == 'frame' && isKitObject(object)) {
      child = _kitShell(context, object, child);
      child = _withPort(context, object, child);
    }
    if (object.rotation != 0) {
      child = Transform.rotate(angle: object.rotation, child: child);
    }
    return Positioned(left: topLeft.dx, top: topLeft.dy, child: child);
  }

  bool _selectedKitContains(SceneObject frame) {
    final id = selectedId;
    if (id == null) {
      return false;
    }
    if (id == frame.id) {
      return true;
    }
    for (final object in objects) {
      if (object.id != id) {
        continue;
      }
      return kitIdOf(object) == kitIdOf(frame) &&
          kitChildBelongsToFrame(object, frame);
    }
    return false;
  }

  Widget _llmChrome(BuildContext context, SceneObject frame, Widget child) {
    final tokens = PaintScope.of(context);
    final zoom = camera.zoom;
    final body = _bodyForFrame(frame);
    final typed = body?.props['prompt']?.toString().trim() ?? '';
    final linked = body == null
        ? ''
        : llmCableInput(
            SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
            body.id,
          ).trim();
    final prompt = linked.isNotEmpty ? linked : typed;
    final reply = body?.props['reply']?.toString().trim() ?? '';
    final error = body?.props['error']?.toString().trim() ?? '';
    final model = body?.props['model']?.toString().trim() ?? '';
    final tools = _toolsFor(body?.id);
    final contextNames = _contextFor(body?.id);
    final output = error.isNotEmpty ? error : reply;
    final barH = 32.0 * zoom;
    final labelSize = 11.0 * zoom;
    final accent = kitAccentColor(frame);
    final hairline = kitAccentHairline(accent);
    return Stack(
      children: [
        child,
        _kitBar(
          frame: frame,
          accent: accent,
          hairline: hairline,
          tokens: tokens,
          zoom: zoom,
          trailing: model.isEmpty ? 'select a model' : model,
          barKey: const Key('llm-kit-chrome'),
          iconKey: const Key('llm-kit-mark'),
        ),
        Positioned(
          left: 10 * zoom,
          right: 10 * zoom,
          top: barH + 8 * zoom,
          bottom: 8 * zoom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _region(
                key: const Key('llm-kit-input-region'),
                tokens: tokens,
                label: 'Input',
                body: prompt,
                zoom: zoom,
                labelSize: labelSize,
              ),
              _rule(hairline, zoom),
              _region(
                key: const Key('llm-kit-context-region'),
                tokens: tokens,
                label: 'Context',
                body: contextNames,
                zoom: zoom,
                labelSize: labelSize,
              ),
              _rule(hairline, zoom),
              _region(
                key: const Key('llm-kit-tools-region'),
                tokens: tokens,
                label: 'Tools',
                body: tools.join('\n'),
                zoom: zoom,
                labelSize: labelSize,
              ),
              _rule(hairline, zoom),
              _region(
                key: const Key('llm-kit-output-region'),
                tokens: tokens,
                label: 'Output',
                body: output,
                zoom: zoom,
                labelSize: labelSize,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rule(Color hairline, double zoom) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 * zoom),
      child: ColoredBox(
        color: hairline,
        child: SizedBox(height: 1 * zoom),
      ),
    );
  }

  Widget _toolChrome(BuildContext context, SceneObject frame, Widget child) {
    final tokens = PaintScope.of(context);
    final zoom = camera.zoom;
    final accent = kitAccentColor(frame);
    final hairline = kitAccentHairline(accent);
    return Stack(
      children: [
        child,
        _kitBar(
          frame: frame,
          accent: accent,
          hairline: hairline,
          tokens: tokens,
          zoom: zoom,
          title: _toolTitle(frame),
          trailing: _toolName(frame),
        ),
      ],
    );
  }

  Widget _namedChrome(BuildContext context, SceneObject frame, Widget child) {
    final tokens = PaintScope.of(context);
    final zoom = camera.zoom;
    final accent = kitAccentColor(frame);
    final hairline = kitAccentHairline(accent);
    return Stack(
      children: [
        child,
        _kitBar(
          frame: frame,
          accent: accent,
          hairline: hairline,
          tokens: tokens,
          zoom: zoom,
        ),
        if (kitIdOf(frame) == boardTextKitId)
          Positioned(
            right: 16 * zoom,
            top:
                (frame.height - textOutputInset) * zoom -
                kitLabelSize * zoom / 2,
            child: Text(
              'Output',
              style: TextStyle(
                color: tokens.muted,
                fontSize: kitLabelSize * zoom,
                letterSpacing: 0.4 * zoom,
              ),
            ),
          ),
      ],
    );
  }

  Widget _kitBar({
    required SceneObject frame,
    required Color accent,
    required Color hairline,
    required PaintTokens tokens,
    required double zoom,
    String trailing = '',
    String? title,
    Key? barKey,
    Key? iconKey,
  }) {
    final label =
        title ??
        kitDisplayName(
          SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
          frame,
        );
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 32.0 * zoom,
      child: DecoratedBox(
        key: barKey,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          border: Border(
            bottom: BorderSide(color: hairline, width: zoom),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8 * zoom),
          child: Row(
            children: [
              KitIcon(
                key: iconKey,
                kind: kitIconForKitId(kitIdOf(frame)),
                color: accent,
                size: 12.0 * zoom,
              ),
              SizedBox(width: 6 * zoom),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.ink,
                    fontSize: 12.0 * zoom,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing.isNotEmpty) ...[
                SizedBox(width: 8 * zoom),
                Flexible(
                  child: Text(
                    trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: tokens.muted,
                      fontSize: 10.0 * zoom,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _toolTitle(SceneObject frame) {
    final toolName = _toolName(frame);
    final stored = kitDisplayName(
      SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
      frame,
    );
    if (toolName.isNotEmpty && stored == toolName) {
      return 'Tool';
    }
    return stored;
  }

  String _toolName(SceneObject frame) {
    for (final object in objects) {
      if (!kitChildBelongsToFrame(object, frame)) {
        continue;
      }
      final name = object.props['toolName']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        return name;
      }
    }
    return '';
  }

  Widget _kitShell(BuildContext context, SceneObject frame, Widget child) {
    final zoom = camera.zoom;
    final radius = kitCornerRadius(frame) * zoom;
    final selected = _selectedKitContains(frame);
    final accent = kitAccentColor(frame);
    return DecoratedBox(
      key: ValueKey('kit-card-${frame.id}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? accent : kitAccentHairline(accent),
          width: zoom,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }

  Widget _region({
    required Key key,
    required PaintTokens tokens,
    required String label,
    required String body,
    required double zoom,
    required double labelSize,
  }) {
    return Expanded(
      child: KeyedSubtree(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: TextStyle(
                color: tokens.muted,
                fontSize: labelSize,
                letterSpacing: 0.4 * zoom,
              ),
            ),
            SizedBox(height: 4 * zoom),
            Expanded(
              child: Text(
                body,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.ink, fontSize: 12.0 * zoom),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _withPort(BuildContext context, SceneObject frame, Widget child) {
    final ports = [
      for (final port in kitPorts(
        SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
      ))
        if (port.frameId == frame.id) port,
    ];
    if (ports.isEmpty) {
      return child;
    }
    final zoom = camera.zoom;
    final accent = kitAccentColor(frame);
    final diameter = 11.0 * zoom;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        for (final port in ports)
          Positioned(
            left: (port.center.dx - frame.x) * zoom - diameter / 2,
            top: (port.center.dy - frame.y) * zoom - diameter / 2,
            width: diameter,
            height: diameter,
            child: _portMark(accent, zoom, port: port),
          ),
      ],
    );
  }

  Widget _portMark(Color accent, double zoom, {required KitPort port}) {
    return DecoratedBox(
      key: ValueKey('${port.kind.name}-${port.frameId}'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF161618),
        border: Border.all(color: accent, width: 1.25 * zoom),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.55),
            blurRadius: 8 * zoom,
            spreadRadius: 0.5 * zoom,
          ),
        ],
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          child: SizedBox(width: 3.5 * zoom, height: 3.5 * zoom),
        ),
      ),
    );
  }

  String _contextFor(String? bodyId) {
    if (bodyId == null) {
      return '';
    }
    final names = <String>[];
    for (final object in objects) {
      if (object.props[skapieRoleProp] != 'frame') {
        continue;
      }
      if (kitIdOf(object) != boardTextKitId) {
        continue;
      }
      if (textConnectedLlmId(object) != bodyId) {
        continue;
      }
      if (textConnectedPort(object) != llmContextPort) {
        continue;
      }
      names.add(
        kitDisplayName(
          SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
          object,
        ),
      );
    }
    return names.join('\n');
  }

  SceneObject? _bodyForFrame(SceneObject frame) {
    for (final object in objects) {
      if (isLlmKitObject(object) &&
          object.props[skapieRoleProp] == 'body' &&
          llmBodyBelongsToFrame(object, frame)) {
        return object;
      }
    }
    return null;
  }

  List<String> _toolsFor(String? bodyId) {
    if (bodyId == null) {
      return const [];
    }
    return llmAttachedToolNames(
      SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
      bodyId,
    );
  }
}
