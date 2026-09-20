import 'package:flutter/material.dart';
import 'package:skapie/registry/object_registry.dart';
import 'package:skapie/registry/object_type.dart';
import 'package:skapie/scene/scene.dart';

const String boxTypeId = 'box';
const String textTypeId = 'text';
const String buttonTypeId = 'button';

ObjectRegistry createBuiltinRegistry() {
  final registry = ObjectRegistry();
  registry
    ..register(_boxType)
    ..register(_textType)
    ..register(_buttonType)
    ..register(_debugRectType);
  return registry;
}

final _boxType = ObjectType(
  typeId: boxTypeId,
  displayName: 'Box',
  defaultProps: const {'fill': '#7AA3C7', 'cornerRadius': 8, 'opacity': 1},
  builder: (context, object, ctx) {
    final fill = _colorProp(object.props, 'fill', const Color(0xFF7AA3C7));
    final radius = _doubleProp(object.props, 'cornerRadius', 8);
    final opacity = _doubleProp(object.props, 'opacity', 1).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  },
);

final _textType = ObjectType(
  typeId: textTypeId,
  displayName: 'Text',
  defaultProps: const {'content': 'Text', 'fontSize': 18, 'color': '#1B1B1B'},
  builder: (context, object, ctx) {
    final content = _stringProp(object.props, 'content', 'Text');
    final fontSize = _doubleProp(object.props, 'fontSize', 18);
    final color = _colorProp(object.props, 'color', const Color(0xFF1B1B1B));
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      child: Text(
        content,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
    );
  },
);

final _buttonType = ObjectType(
  typeId: buttonTypeId,
  displayName: 'Button',
  defaultProps: const {'label': 'Button'},
  builder: (context, object, ctx) {
    final label = _stringProp(object.props, 'label', 'Button');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2F5D50),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  },
);

final _debugRectType = ObjectType(
  typeId: debugRectType,
  displayName: 'Debug rect',
  defaultProps: const {},
  builder: (context, object, ctx) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.outlineVariant.withValues(alpha: 0.45),
        border: Border.all(color: colors.outline),
      ),
    );
  },
);

String _stringProp(Map<String, Object?> props, String key, String fallback) {
  final value = props[key];
  return value is String && value.isNotEmpty ? value : fallback;
}

double _doubleProp(Map<String, Object?> props, String key, double fallback) {
  final value = props[key];
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

Color _colorProp(Map<String, Object?> props, String key, Color fallback) {
  final value = props[key];
  if (value is int) {
    return Color(value);
  }
  if (value is String) {
    var hex = value.replaceFirst('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) {
      return Color(parsed);
    }
  }
  return fallback;
}
