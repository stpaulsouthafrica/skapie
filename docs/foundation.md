# Skapie foundation doctrine

These rules bind every phase. If a change fights them, the change is wrong.

## One mutation path

Scene data changes only through `SceneStore.apply(SceneOp)`. Widgets, kits, and the agent must not poke document fields. Phase 6 Kit API must wrap these ops, not bypass them. Live camera pan/zoom is canvas state; `noteCamera` only snapshots it for save.

## Scene is the source of truth

The scene document is what is real. The canvas, inspector, and any agent memory are views or proposals. Reload from scene and the UI must reconstruct. Debug rectangles are drawn from `SceneStore` scene objects, not from widget state. Camera pan limits read those objects and clamp viewport state only — they never mutate the scene.

Vocabulary: scene items are **scene objects**. **Graph node** is reserved for a future cable/port graph. Full table: [glossary](glossary.md).

## Registry over fantasy

v1 does not generate arbitrary Dart widgets at runtime. Known types live in a registry; kits register types; the renderer draws only what the registry knows. Unknown type → explicit fallback, not a guessed widget tree.

## Tests at the spine

Every phase ships tests for the seam it introduces (document load/save, mutation, registry lookup, canvas camera, tool dispatch). UI chrome is not a substitute for spine tests. A phase is not done if the new seam can regress silently.

## Docs match code

README, this file, and `docs/` describe what the tree actually does. No APIs, folders, or phases documented as shipped unless they exist. When code moves, docs move in the same change.

## Acceptance before next phase

Do not start phase _n+1_ until phase _n_ meets its acceptance criteria: `flutter analyze` clean, `flutter test` green, and the phase’s stated UX/behavior checks. Phase 4+ is blocked until the current phase gate is green.

## Phase 1 gate — done

- macOS desktop shell launches with branding chrome.
- Folder layout for `app`, `canvas`, `scene`, `registry`, `kit_api`, `agent`, `shared`, `docs`, `kits` exists; later layers stay stubs until their phase.

## Phase 2 gate — done

- Camera is the viewport spine: `CanvasCamera.panScreen` / `zoomAt` / `reset`.
- Screen origin is viewport top-left; world shares those axes; `offset` is the world point at the viewport center; zoom is world-to-screen scale, clamped 0.25–4.0. World `(0,0)` is the **world origin**.

## Phase 3 gate (current)

- Scene document in `lib/scene/`. Mutations only via `SceneStore.apply`.
- JSON `schemaVersion` required; unknown fields ignored (tolerant).
- Undo/redo with snapshot strategy; new apply clears redo.
- Persistence: `.skapie/scene.json`. Load on startup; save after successful apply/undo/redo. Writes `"objects"`; still reads legacy `"nodes"` (`schemaVersion` 1).
- Debug gray rects from scene object frames only — not a registry.
- `flutter analyze` clean; `flutter test` covers JSON round-trip, add/remove, frame/props, undo/redo, missing-file load, legacy `nodes` key, camera transforms, smoke.

Phase 4+ stays blocked until this gate is green. Do not implement registry widgets, kits, selection, or the agent here.
