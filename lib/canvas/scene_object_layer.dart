import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/canvas_camera.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/paint/cables/cable_motion.dart';
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
    this.motion,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final List<SceneObject> objects;
  final ObjectRegistry registry;
  final String? selectedId;
  final Offset previewDelta;
  final Set<String> previewIds;
  final CableMotion? motion;

  @override
  Widget build(BuildContext context) {
    final motion = this.motion;
    if (motion == null) {
      return _layout(context);
    }
    return ListenableBuilder(
      listenable: motion,
      builder: (context, _) => _layout(context),
    );
  }

  Widget _layout(BuildContext context) {
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
    final reply = body?.props['reply']?.toString().trim() ?? '';
    final error = body?.props['error']?.toString().trim() ?? '';
    final model = body?.props['model']?.toString().trim() ?? '';
    final tools = _toolLines(body?.id);
    final contextNames = _contextLines(body?.id);
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
                lines: _inputLines(body),
                glow: accent,
                zoom: zoom,
                labelSize: labelSize,
              ),
              _rule(hairline, zoom),
              _region(
                key: const Key('llm-kit-context-region'),
                tokens: tokens,
                label: 'Context',
                lines: contextNames,
                glow: accent,
                zoom: zoom,
                labelSize: labelSize,
              ),
              _rule(hairline, zoom),
              _region(
                key: const Key('llm-kit-tools-region'),
                tokens: tokens,
                label: 'Tools',
                lines: tools,
                glow: accent,
                zoom: zoom,
                labelSize: labelSize,
              ),
              _rule(hairline, zoom),
              _region(
                key: const Key('llm-kit-output-region'),
                tokens: tokens,
                label: '',
                lines: [if (output.isNotEmpty) _KitLine(output)],
                glow: accent,
                zoom: zoom,
                labelSize: labelSize,
              ),
            ],
          ),
        ),
        _outputCaption(tokens, zoom, frame),
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
          _outputCaption(tokens, zoom, frame),
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

  Widget _outputCaption(PaintTokens tokens, double zoom, SceneObject frame) {
    return Positioned(
      right: 16 * zoom,
      top: (frame.height - textOutputInset) * zoom - kitLabelSize * zoom / 2,
      child: Text(
        'Output',
        style: TextStyle(
          color: tokens.muted,
          fontSize: kitLabelSize * zoom,
          letterSpacing: 0.4 * zoom,
        ),
      ),
    );
  }

  Widget _region({
    required Key key,
    required PaintTokens tokens,
    required String label,
    required List<_KitLine> lines,
    required Color glow,
    required double zoom,
    required double labelSize,
  }) {
    final style = TextStyle(color: tokens.ink, fontSize: 12.0 * zoom);
    final spans = <InlineSpan>[
      for (final line in lines)
        if (_visible(line))
          TextSpan(
            text: '${line.text}\n',
            style: arrivalTextStyle(
              base: style,
              glowColor: glow,
              shown: _shown(line.cableId),
              glow: motion?.glow(line.cableId) ?? 0,
            ),
          ),
    ];
    return Expanded(
      child: KeyedSubtree(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (label.isNotEmpty) ...[
              Text(
                label,
                style: TextStyle(
                  color: tokens.muted,
                  fontSize: labelSize,
                  letterSpacing: 0.4 * zoom,
                ),
              ),
              SizedBox(height: 4 * zoom),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(children: spans),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _visible(_KitLine line) {
    return line.text.isNotEmpty && _shown(line.cableId) > 0;
  }

  double _shown(String? cableId) => motion?.shown(cableId) ?? 1;

  SceneDocument get _preview =>
      SceneDocument(id: 'preview', schemaVersion: 1, objects: objects);

  List<_KitLine> _inputLines(SceneObject? body) {
    if (body == null) {
      return const [];
    }
    final document = _preview;
    final linked = <_KitLine>[];
    for (final frame in textFrames(document)) {
      if (!kitHasLink(frame, to: body.id, port: llmInputPort)) {
        continue;
      }
      final content = textKitContent(document, frame).trim();
      if (content.isEmpty) {
        continue;
      }
      linked.add(
        _KitLine(content, cableId: '${frame.id}|${body.id}|$llmInputPort'),
      );
    }
    if (linked.isEmpty) {
      for (final other in llmBodies(document)) {
        if (!kitHasLink(other, to: body.id, port: llmInputPort)) {
          continue;
        }
        final reply = other.props['reply']?.toString().trim() ?? '';
        if (reply.isEmpty) {
          continue;
        }
        linked.add(
          _KitLine(reply, cableId: '${other.id}|${body.id}|$llmInputPort'),
        );
      }
    }
    if (linked.isNotEmpty && linked.any((line) => _shown(line.cableId) > 0)) {
      return linked;
    }
    final typed = body.props['prompt']?.toString().trim() ?? '';
    if (typed.isNotEmpty) {
      return [_KitLine(typed)];
    }
    return linked;
  }

  List<_KitLine> _contextLines(String? bodyId) {
    if (bodyId == null) {
      return const [];
    }
    final document = _preview;
    return [
      for (final frame in textFrames(document))
        if (kitHasLink(frame, to: bodyId, port: llmContextPort))
          _KitLine(
            kitDisplayName(document, frame),
            cableId: '${frame.id}|$bodyId|$llmContextPort',
          ),
    ];
  }

  List<_KitLine> _toolLines(String? bodyId) {
    if (bodyId == null) {
      return const [];
    }
    final lines = <_KitLine>[];
    for (final object in objects) {
      if (object.props[skapieRoleProp] != 'frame') {
        continue;
      }
      if (!kitHasLink(object, to: bodyId, port: llmToolsPort)) {
        continue;
      }
      final name = _toolName(object);
      if (name.isEmpty) {
        continue;
      }
      lines.add(_KitLine(name, cableId: '${object.id}|$bodyId|$llmToolsPort'));
    }
    return lines;
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
}

class _KitLine {
  const _KitLine(this.text, {this.cableId});

  final String text;
  final String? cableId;
}
