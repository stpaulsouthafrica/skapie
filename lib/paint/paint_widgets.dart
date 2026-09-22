import 'package:flutter/material.dart';
import 'package:skapie/paint/paint_scope.dart';
import 'package:skapie/paint/paint_tokens.dart';

class PaintPanel extends StatelessWidget {
  const PaintPanel({
    super.key,
    required this.child,
    this.padding,
    this.capsule = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool capsule;

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panel,
        borderRadius: BorderRadius.circular(
          capsule ? 999 : PaintTokens.radiusPanel,
        ),
        border: Border.all(color: tokens.hairline),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(12),
        child: child,
      ),
    );
  }
}

class PaintButton extends StatelessWidget {
  const PaintButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.richLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final InlineSpan? richLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final enabled = onPressed != null;
    final bg = filled
        ? tokens.accent.withValues(alpha: enabled ? 1 : 0.4)
        : Colors.transparent;
    final fg = filled ? tokens.onAccent : tokens.ink;
    return PaintHover(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(PaintTokens.radiusField),
            border: Border.all(
              color: filled ? Colors.transparent : tokens.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: richLabel == null
                ? Text(
                    label,
                    style: TextStyle(
                      color: fg.withValues(alpha: enabled ? 1 : 0.4),
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  )
                : Text.rich(
                    richLabel!,
                    style: TextStyle(
                      color: fg.withValues(alpha: enabled ? 1 : 0.4),
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class PaintIconButton extends StatelessWidget {
  const PaintIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    final button = PaintHover(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: tokens.ink),
        ),
      ),
    );
    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: tooltip, child: button);
  }
}

class PaintTextField extends StatelessWidget {
  const PaintTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.enabled = true,
    this.obscure = false,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool enabled;
  final bool obscure;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    return PaintHover(
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: TextStyle(color: tokens.ink, fontSize: 13),
        cursorColor: tokens.accent,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class PaintHover extends StatefulWidget {
  const PaintHover({super.key, required this.child, this.radius});

  final Widget child;
  final double? radius;

  @override
  State<PaintHover> createState() => _PaintHoverState();
}

class _PaintHoverState extends State<PaintHover> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _hover
              ? tokens.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(
            widget.radius ?? PaintTokens.radiusField,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class PaintChip extends StatelessWidget {
  const PaintChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = PaintScope.of(context);
    return PaintHover(
      radius: 999,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.22)
                : tokens.canvas.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? tokens.accent : tokens.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: TextStyle(color: tokens.ink, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }
}
