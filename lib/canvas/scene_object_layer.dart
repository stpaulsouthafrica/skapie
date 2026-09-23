import 'package:flutter/material.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/cable_activity.dart';
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
    this.activity = CableActivity.idle,
    this.glow,
    this.resizeFrameId,
    this.resizeHeight,
  });

  final CanvasCamera camera;
  final Size viewportSize;
  final List<SceneObject> objects;
  final ObjectRegistry registry;
  final String? selectedId;
  final Offset previewDelta;
  final Set<String> previewIds;
  final CableActivity activity;
  final ActivityGlow? glow;
  final String? resizeFrameId;
  final double? resizeHeight;

  @override
  Widget build(BuildContext context) {
    final glow = this.glow;
    if (glow == null) {
      return _layout(context, const {});
    }
    return AnimatedBuilder(
      animation: glow,
      builder: (context, _) => _layout(context, glow.levels),
    );
  }

  Widget _layout(BuildContext context, Map<String, double> levels) {
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
        children: [
          for (final object in ordered) _placed(context, object, levels),
        ],
      ),
    );
  }

  double _level(Map<String, double> levels, String frameId) =>
      levels[frameId] ?? 0;

  Widget _placed(
    BuildContext context,
    SceneObject object,
    Map<String, double> levels,
  ) {
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
    final isTextBody = kitIdOf(object) == boardTextKitId && role == 'body';
    final isConversationBody =
        kitIdOf(object) == harnessConversationKitId && role == 'body';
    final hide =
        isLlmBody || isTextBody || isConversationBody || role == 'grant';
    final paintedHeight = object.id == resizeFrameId && resizeHeight != null
        ? resizeHeight!
        : object.height;
    Widget child = SizedBox(
      width: object.width * camera.zoom,
      height: paintedHeight * camera.zoom,
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
    final glow = _level(levels, object.id);
    if (role == 'frame' && isKitObject(object)) {
      child = _kitShell(context, object, child, glow: glow);
      child = _withPort(context, object, child, glow);
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
    final model = body?.props['model']?.toString().trim() ?? '';
    final document = _preview;
    final status = llmRunStatusOf(
      body,
      running: activity.runningBodyId == body?.id,
    );
    final accent = kitAccentColor(frame);
    final hairline = kitAccentHairline(accent);
    final rows = [
      for (final spec in kitPortSpecsFor(frame))
        if (spec.placement.anchor == PortAnchor.row)
          (spec.kind, spec.label, Key('llm-kit-${spec.id}-region')),
    ];
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
          showRun: true,
          running: activity.runningBodyId == body?.id,
        ),
        Positioned(
          left: 16 * zoom,
          right: 16 * zoom,
          top: (kitBarWorld + llmPortTop) * zoom,
          bottom: (llmResizeHandle + 8) * zoom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0)
                  SizedBox(
                    height: kitRuleExtent * zoom,
                    child: Center(
                      child: ColoredBox(
                        color: tokens.hairline,
                        child: SizedBox(height: zoom, width: double.infinity),
                      ),
                    ),
                  ),
                Expanded(
                  child: index == rows.length - 1
                      ? _statusOutputRow(
                          tokens: tokens,
                          accent: accent,
                          zoom: zoom,
                          status: status,
                          output: _portLabel(
                            rows[index].$2,
                            llmConnectionCount(
                              document,
                              body?.id,
                              rows[index].$1,
                            ),
                            many: llmPortAcceptsMany(rows[index].$1),
                          ),
                        )
                      : _portRow(
                          key: rows[index].$3,
                          tokens: tokens,
                          zoom: zoom,
                          label: _portLabel(
                            rows[index].$2,
                            llmConnectionCount(
                              document,
                              body?.id,
                              rows[index].$1,
                            ),
                            many: llmPortAcceptsMany(rows[index].$1),
                          ),
                          alignEnd: kitPortIsOutput(rows[index].$1),
                        ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 3 * zoom,
          child: Center(
            child: DecoratedBox(
              key: const Key('llm-resize-handle'),
              decoration: BoxDecoration(
                color: tokens.muted.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2 * zoom),
              ),
              child: SizedBox(width: 28 * zoom, height: 4 * zoom),
            ),
          ),
        ),
      ],
    );
  }

  String _portLabel(String label, int count, {required bool many}) {
    if (!many || count == 0) {
      return label;
    }
    return '$label · $count';
  }

  Color _statusColor(PaintTokens tokens, Color accent, LlmRunStatus status) {
    return switch (status) {
      LlmRunStatus.running || LlmRunStatus.waitingForReview => accent,
      LlmRunStatus.failed => tokens.danger,
      _ => tokens.muted,
    };
  }

  Widget _statusOutputRow({
    required PaintTokens tokens,
    required Color accent,
    required double zoom,
    required LlmRunStatus status,
    required String output,
  }) {
    final style = TextStyle(
      color: tokens.muted,
      fontSize: kitLabelSize * zoom,
      letterSpacing: 0.4 * zoom,
    );
    return Row(
      key: const Key('llm-kit-output-region'),
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Status: '),
                TextSpan(
                  text: llmRunStatusLabel(status),
                  style: TextStyle(color: _statusColor(tokens, accent, status)),
                ),
              ],
            ),
            key: const Key('llm-kit-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        Text(output, maxLines: 1, style: style),
      ],
    );
  }

  Widget _portRow({
    required Key key,
    required PaintTokens tokens,
    required double zoom,
    required String label,
    bool alignEnd = false,
  }) {
    return SizedBox(
      key: key,
      height: llmPortRowHeight * zoom,
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.muted,
            fontSize: kitLabelSize * zoom,
            letterSpacing: 0.4 * zoom,
          ),
        ),
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
        Positioned(
          left: 12 * zoom,
          right: 16 * zoom,
          top:
              (kitBarWorld + (frame.height - kitBarWorld) / 2) * zoom -
              kitLabelSize * zoom / 2,
          child: Row(
            children: [
              if (frame.props['requiresRepository'] == true)
                Text(
                  'Repository',
                  style: TextStyle(
                    color: tokens.muted,
                    fontSize: kitLabelSize * zoom,
                    letterSpacing: 0.4 * zoom,
                  ),
                ),
              const Spacer(),
              Text(
                'LLM',
                style: TextStyle(
                  color: tokens.muted,
                  fontSize: kitLabelSize * zoom,
                  letterSpacing: 0.4 * zoom,
                ),
              ),
            ],
          ),
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
          Positioned.fill(
            child: _previewFooter(
              tokens,
              zoom,
              frame,
              content: _bodyContent(frame, boardTextKitId),
              leading: 'In',
              trailing: 'Out',
            ),
          ),
        if (kitIdOf(frame) == harnessConversationKitId)
          Positioned.fill(
            child: _previewFooter(
              tokens,
              zoom,
              frame,
              content: _bodyContent(frame, harnessConversationKitId),
              leading: 'In',
              trailing: 'Out',
            ),
          ),
        if (kitIdOf(frame) == codingRepositoryKitId)
          _outputCaption(tokens, zoom, frame, label: 'In / Out'),
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
    bool showRun = false,
    bool running = false,
  }) {
    final label =
        title ??
        kitDisplayName(
          SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
          frame,
        );
    final iconKind = kitIconForKitId(kitIdOf(frame));
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
        child: showRun
            ? Stack(
                fit: StackFit.expand,
                alignment: Alignment.centerLeft,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: 8 * zoom,
                      right: (llmRunButtonRight + llmRunButtonSlot) * zoom,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        KitIcon(
                          key: iconKey,
                          kind: iconKind,
                          color: accent,
                          size:
                              (iconKind == KitIconKind.text ? 15.0 : 12.0) *
                              zoom,
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
                              height: 1,
                            ),
                          ),
                        ),
                        if (trailing.isNotEmpty)
                          Expanded(
                            child: Text(
                              trailing,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: tokens.muted,
                                fontSize: 10.0 * zoom,
                                height: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: llmRunButtonRight * zoom,
                    top: 0,
                    bottom: 0,
                    width: llmRunButtonSlot * zoom,
                    child: Center(
                      child: Icon(
                        key: const Key('llm-kit-run-button'),
                        running ? Icons.hourglass_top : Icons.play_arrow,
                        size: 16 * zoom,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              )
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: 8 * zoom),
                child: Row(
                  children: [
                    KitIcon(
                      key: iconKey,
                      kind: iconKind,
                      color: accent,
                      size: (iconKind == KitIconKind.text ? 15.0 : 12.0) * zoom,
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

  Widget _kitShell(
    BuildContext context,
    SceneObject frame,
    Widget child, {
    required double glow,
  }) {
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
        boxShadow: glow > 0.02
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.42 * glow),
                  blurRadius: 18 * zoom,
                  spreadRadius: glow * zoom,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }

  Widget _previewFooter(
    PaintTokens tokens,
    double zoom,
    SceneObject frame, {
    required String content,
    required String trailing,
    String? leading,
  }) {
    final summary = textKitSummary(content);
    final style = TextStyle(
      color: tokens.ink,
      fontSize: 13 * zoom,
      height: 1.25,
    );
    return Stack(
      children: [
        Positioned(
          left: 12 * zoom,
          right: 12 * zoom,
          top: (kitBarWorld + 8) * zoom,
          bottom: (textOutputInset + kitLabelSize + 8) * zoom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.firstLine,
                key: const Key('text-kit-first-line'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
              if (summary.moreLines > 0)
                Text(
                  summary.moreLabel,
                  key: const Key('text-kit-more-lines'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    color: tokens.muted,
                    fontSize: 11 * zoom,
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 10 * zoom,
          right: 10 * zoom,
          bottom: (textOutputInset + kitLabelSize / 2 + 8) * zoom,
          child: ColoredBox(
            color: tokens.hairline,
            child: SizedBox(height: zoom),
          ),
        ),
        if (leading != null)
          Positioned(
            left: 16 * zoom,
            top:
                (frame.height - textOutputInset) * zoom -
                kitLabelSize * zoom / 2,
            child: Text(
              leading,
              style: TextStyle(
                color: tokens.muted,
                fontSize: kitLabelSize * zoom,
                letterSpacing: 0.4 * zoom,
              ),
            ),
          ),
        Positioned(
          right: 16 * zoom,
          top:
              (frame.height - textOutputInset) * zoom - kitLabelSize * zoom / 2,
          child: Text(
            trailing,
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

  String _bodyContent(SceneObject frame, String kitId) {
    for (final object in objects) {
      if (object.type != textTypeId ||
          object.props[skapieRoleProp] == 'frame') {
        continue;
      }
      if (kitChildBelongsToFrame(object, frame) && kitIdOf(object) == kitId) {
        return object.props['content']?.toString() ?? '';
      }
    }
    return '';
  }

  Widget _outputCaption(
    PaintTokens tokens,
    double zoom,
    SceneObject frame, {
    String label = 'Output',
  }) {
    return Positioned(
      right: 16 * zoom,
      top: (frame.height - textOutputInset) * zoom - kitLabelSize * zoom / 2,
      child: Text(
        label,
        style: TextStyle(
          color: tokens.muted,
          fontSize: kitLabelSize * zoom,
          letterSpacing: 0.4 * zoom,
        ),
      ),
    );
  }

  SceneDocument get _preview =>
      SceneDocument(id: 'preview', schemaVersion: 1, objects: objects);

  Widget _withPort(
    BuildContext context,
    SceneObject frame,
    Widget child,
    double glow,
  ) {
    final ports = [
      for (final port in kitPorts(
        SceneDocument(id: 'preview', schemaVersion: 1, objects: objects),
        resizeFrameId: resizeFrameId,
        resizeHeight: resizeHeight,
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
            child: _portMark(accent, zoom, port: port, glow: glow),
          ),
      ],
    );
  }

  Widget _portMark(
    Color accent,
    double zoom, {
    required KitPort port,
    required double glow,
  }) {
    final lit = glow.clamp(0.0, 1.0);
    return DecoratedBox(
      key: ValueKey('${port.kind.name}-${port.frameId}'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(const Color(0xFF161618), accent, 0.4 * lit),
        border: Border.all(
          color: Color.lerp(accent, const Color(0xFFFFF8EC), 0.45 * lit)!,
          width: (1.25 + 0.2 * lit) * zoom,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.55 + 0.25 * lit),
            blurRadius: (8 + 6 * lit) * zoom,
            spreadRadius: (0.5 + lit) * zoom,
          ),
        ],
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(accent, const Color(0xFFFFF8EC), 0.5 * lit),
          ),
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
