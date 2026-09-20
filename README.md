# Skapie

Skapie is a Flutter desktop app: a canvas over an infinite world, a scene document of scene objects, and kits (capability instances; kit packages live on disk later). v1 does not generate arbitrary Dart widgets at runtime: an agent will edit scene data, and a registry will render known types.

This repository is **Phase 3 of 10** — macOS desktop shell, canvas viewport, and a scene document (ops, undo/redo, JSON load/save). There is no widget registry, kit API, or agent yet.

## Run on macOS

Requires [Flutter](https://docs.flutter.dev/get-started/install) with desktop enabled.

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter run -d macos
```

You should get a window titled **Skapie Canvas** with a thin **Skapie** bar and a canvas that fills the rest of the window.

**Pan:** drag the empty canvas, or two-finger trackpad pan. Pan is hard-clamped so the viewport center stays in padded content bounds (empty scene: 2000×2000 around the world origin). **Zoom:** mouse wheel or trackpad pinch; zoom is anchored to the pointer, not the viewport center. After zoom, offset is re-clamped. **Reset:** `0` or `Cmd+0` (also `Ctrl+0` / numpad `0`) restores zoom `100%` and recenters on the **world origin**, then clamps. Zoom is clamped to 25%–400%. A zoom percentage HUD sits in the corner; a dot grid and origin cross mark world `(0,0)`.

**Scene (dev):** **Add debug rect** or press `N` to insert a gray `debug.rect` scene object centered on the world point currently at the viewport center (the camera `offset`). `Cmd+Z` / `Cmd+Shift+Z` undo/redo. These are temporary debug rectangles, not real widgets.

**Transforms:** screen origin is the viewport top-left (Flutter: +x right, +y down). World uses the same axes. World `(0,0)` is the **world origin**. The camera `offset` is the world point shown at the viewport center — not another name for the origin.

**Save file:** `.skapie/scene.json` under the process working directory (project root when launched from this repo). Loaded on startup if present. Files write `"objects"`; older files with `"nodes"` still load (`schemaVersion` 1).

## Foundation gates

Skapie is built phase by phase. **Phase 4+ is blocked until the current phase gate is green.** Doctrine lives in [`docs/foundation.md`](docs/foundation.md). Scene details are in [`docs/scene.md`](docs/scene.md). Vocabulary is in [`docs/glossary.md`](docs/glossary.md).

**Phase 1 gate:** macOS shell + folder stubs — done.

**Phase 2 gate:** infinite canvas pan/zoom + tested transforms — done.

**Phase 3 gate:** scene model + `SceneStore.apply` + undo/redo + JSON round-trip + `.skapie/scene.json`; debug rects only; `flutter analyze` clean; `flutter test` green.

## Docs

- [`docs/glossary.md`](docs/glossary.md) — canvas, world origin, scene object, kit, graph node
- [`docs/foundation.md`](docs/foundation.md) — doctrine and phase gates
- [`docs/scene.md`](docs/scene.md) — document model, ops, file path, world origin
