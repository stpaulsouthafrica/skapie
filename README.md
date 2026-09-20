# Skapie

Skapie is a Flutter desktop app: a canvas over an infinite world, a scene document of scene objects, and kits (capability instances; kit packages live on disk later). v1 does not generate arbitrary Dart widgets at runtime: an agent will edit scene data, and a registry renders known types.

This repository is **Phase 6 of 10** — canvas, scene, registry, select/move/inspector, and an in-memory Kit API. Kit packages on disk and the agent are not implemented yet.

## Run on macOS

Requires [Flutter](https://docs.flutter.dev/get-started/install) with desktop enabled.

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter run -d macos
```

You should get a window titled **Skapie Canvas** with a thin **Skapie** bar and a canvas that fills the rest of the window.

**Pan:** drag the empty canvas, or two-finger trackpad pan. Pan is hard-clamped so the viewport center stays in padded content bounds (empty scene: 2000×2000 around the world origin). **Zoom:** mouse wheel or trackpad pinch; zoom is anchored to the pointer, not the viewport center. After zoom, offset is re-clamped. **Reset:** `0` or `Cmd+0` (also `Ctrl+0` / numpad `0`) restores zoom `100%` and recenters on the **world origin**, then clamps. Zoom is clamped to 25%–400%. A zoom percentage HUD sits in the corner; a dot grid and origin cross mark world `(0,0)`.

**Scene (dev):** **Add** → Box / Text / Button / Debug rect / **Demo kit: note card**. Adds go through `KitApi` (which calls `SceneStore.apply`). Click an object to select it (outline + inspector). Drag a selected unlocked object to move it. Click empty canvas to pan and clear selection. Delete/Backspace removes the selected object when the canvas is focused. Press `N` for a `debug.rect`. `Cmd+Z` / `Cmd+Shift+Z` undo/redo. Selection is not saved.

**Transforms:** screen origin is the viewport top-left (Flutter: +x right, +y down). World uses the same axes. World `(0,0)` is the **world origin**. The camera `offset` is the world point shown at the viewport center — not another name for the origin.

**Save file:** absolute path under Application Support (`…/skapie/scene.json`) by default. Logged at startup. The top bar shows a short label; hover or **Copy path** for the full path. Not cwd-relative unless you explicitly enable project mode with an **absolute** `SKAPIE_PROJECT_ROOT`. See [`docs/scene.md`](docs/scene.md).

```bash
# default: Application Support
flutter run -d macos

# developer: repo-local scene (absolute root required)
flutter run -d macos \
  --dart-define=SKAPIE_USE_PROJECT_SCENE=true \
  --dart-define=SKAPIE_PROJECT_ROOT=/Users/you/Development/skapie
```

## Foundation gates

Skapie is built phase by phase. **Phase 7+ is blocked until the current phase gate is green.** Doctrine lives in [`docs/foundation.md`](docs/foundation.md). Scene details are in [`docs/scene.md`](docs/scene.md). Registry details are in [`docs/registry.md`](docs/registry.md). Interaction is in [`docs/interaction.md`](docs/interaction.md). Kit API is in [`docs/kit_api.md`](docs/kit_api.md). Vocabulary is in [`docs/glossary.md`](docs/glossary.md).

**Phase 1 gate:** macOS shell + folder stubs — done.

**Phase 2 gate:** infinite canvas pan/zoom + tested transforms — done.

**Phase 3 gate:** scene model + `SceneStore.apply` + undo/redo + JSON round-trip + `.skapie/scene.json` — done.

**Phase 4 gate:** `ObjectRegistry` maps `type` → builder; built-ins `box` / `text` / `button` / `debug.rect`; unknown types placeholder; Add menu via `apply` — done.

**Phase 5 gate:** single select + move (one undo) + overlay inspector (`SetObjectLocked`, no canvas reflow) + MMB pan; selection not in `scene.json` — done.

**Phase 6 gate:** `KitApi` wraps `SceneStore.apply`; in-memory recipes + demo note card; no disk loader; `flutter analyze` clean; `flutter test` green.

## Docs

- [`docs/glossary.md`](docs/glossary.md) — canvas, world origin, scene object, kit, graph node
- [`docs/foundation.md`](docs/foundation.md) — doctrine and phase gates
- [`docs/scene.md`](docs/scene.md) — document model, ops, file path, world origin
- [`docs/registry.md`](docs/registry.md) — type string → builder, unknown placeholder
- [`docs/interaction.md`](docs/interaction.md) — select, move, inspector
- [`docs/kit_api.md`](docs/kit_api.md) — high-level scene mutations, in-memory kits
