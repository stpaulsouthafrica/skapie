# Skapie

Skapie is a Flutter desktop app for an infinite canvas, a scene document, and widget kits (like Pi extensions). v1 does not generate arbitrary Dart widgets at runtime: an agent will edit scene data, and a registry will render known types.

This repository is **Phase 2 of 10** — macOS desktop shell plus an infinite canvas viewport (camera, pan/zoom, grid). There is no scene model, kit API, or agent yet.

## Run on macOS

Requires [Flutter](https://docs.flutter.dev/get-started/install) with desktop enabled.

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter run -d macos
```

You should get a window titled **Skapie Canvas** with a thin **Skapie** bar and a canvas that fills the rest of the window.

**Pan:** drag the empty canvas, or two-finger trackpad pan. **Zoom:** mouse wheel or trackpad pinch; zoom is anchored to the pointer, not the viewport center. **Reset:** `0` or `Cmd+0` (also `Ctrl+0` / numpad `0`) restores zoom `100%` and recenters world origin. Zoom is clamped to 25%–400%. A zoom percentage HUD sits in the corner; a dot grid and origin cross mark world `(0,0)`.

**Transforms:** screen origin is the viewport top-left (Flutter: +x right, +y down). World uses the same axes. The camera `offset` is the world point shown at the viewport center; `zoom` is world-to-screen scale. Default camera places world origin at the center.

## Foundation gates

Skapie is built phase by phase. **Phase 3+ is blocked until the current phase gate is green.** Doctrine (one mutation path, scene as source of truth, registry over fantasy, tests at the spine, docs match code, acceptance before next phase) lives in [`docs/foundation.md`](docs/foundation.md).

**Phase 1 gate:** macOS shell + folder stubs — done.

**Phase 2 gate:** infinite canvas fills the body; pan + zoom-toward-cursor; zoom clamped; grid + origin; transform helpers tested (round-trip, clamp, zoom-at-point); `flutter analyze` clean; `flutter test` green.

## Docs

Foundation doctrine is in [`docs/foundation.md`](docs/foundation.md). Future Kit API documentation will also live in [`docs/`](docs/).
