# Widget registry

The registry maps a scene object’s `type` string to a Flutter builder. It does not own the scene and does not evaluate Dart at runtime.

Unknown types render as a placeholder. The scene document remains the source of truth.

## What it is

`ObjectRegistry` is a map of `typeId` → `ObjectType`.

```dart
typedef SceneObjectBuilder = Widget Function(
  BuildContext context,
  SceneObject object,
  RegistryBuildContext ctx,
);

class ObjectType {
  final String typeId;
  final String displayName;
  final Map<String, Object?> defaultProps;
  final SceneObjectBuilder builder;
}
```

- `register` — duplicate `typeId` throws `StateError`
- `get` / `list` — lookup; no mutation of the scene
- `build` — never throws out to the canvas. Unknown type or a builder failure → `UnknownObjectPlaceholder`

`RegistryBuildContext` currently carries `zoom` only. The canvas still places frames from `x` / `y` / `width` / `height` in world space.

## Built-in types

Registered by `createBuiltinRegistry()`:

| `typeId` | Looks like | Default props |
|---|---|---|
| `box` | filled rounded rectangle | `fill`, `cornerRadius`, `opacity` |
| `text` | label | `content`, `fontSize`, `color` |
| `button` | colored chip with a label | `label` (visual only; no navigation) |
| `debug.rect` | grey outlined rect | none |

Add actions insert a `SceneObject` with that type and those defaults through `SceneStore.apply(AddObject(...))`.

## Unknown types

If `type` is not registered, or a builder throws, the canvas shows `UnknownObjectPlaceholder` (grey box with the type id). It does not crash and does not guess a widget tree.

## Not this phase

- Kit API / kits on disk
- Agent
- Inspector (Phase 5)
- Runtime Dart eval

See [glossary](glossary.md): **scene object** vs **kit** vs **kit package** vs **graph node**.
