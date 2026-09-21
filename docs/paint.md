# Paint

Cosmetic identity for Skapie. The world stays the product. Scene, Kit API, canvas spine, and the agent harness do not live here. New capability belongs in user kits. Paint does not mutate the scene.

## Folder

`lib/paint/`

| File | Role |
|---|---|
| `paint_tokens.dart` | Dark luxury tokens: near-black surfaces, champagne gold accent, type sizes, radii, hairline |
| `paint_widgets.dart` | Thin chrome: button, text field, panel, chip, icon button |
| `paint_theme.dart` | `ThemeData` bridge so existing screens pick up tokens |
| `paint_scope.dart` | Inherited tokens for those widgets |

App code imports paint. Paint does not import the scene, kits, or the agent harness.

The look is fixed: dark + champagne gold. There is no appearance prefs file and no glass/transparency slider. The macOS window is a normal opaque Flutter window.

## Transient chrome

The canvas is full-bleed. There is no top app bar. The chat strip is a capsule about one third of the window width, field only, Return to send. Settings open as a dismissible sheet from `/settings`, `/settings/`, or Cmd+,. Add and the scene path live in that sheet. The inspector is an overlay while something is selected. Nothing non-kit stays parked in the world.

## Not this folder

Kit drop animation, edge ripples, living dots, streaming, MCP, sandbox kits, and a coding-agent kit are later. Do not grow the engine from paint.
