# Skapie foundation doctrine

These rules bind every phase. If a change fights them, the change is wrong.

## One mutation path

Scene data changes only through `SceneStore.apply(SceneOp)`. Widgets, kits, and the agent must not poke document fields. The Kit API wraps these ops; it does not bypass them. Live camera pan/zoom is canvas state; `noteCamera` only snapshots it for save.

## Scene is the source of truth

The scene document is what is real. The canvas, inspector, and any agent memory are views or proposals. Reload from scene and the UI must reconstruct. Selection (`selectedId`) is **UI state only** — not a scene field and not persisted. Camera pan limits read those objects and clamp viewport state only — they never mutate the scene.

Vocabulary: scene items are **scene objects**. **Graph node** is reserved for a future cable/port graph. Full table: [glossary](glossary.md).

## Registry over fantasy

v1 does not generate arbitrary Dart widgets at runtime. Known types live in `ObjectRegistry` (`lib/registry/`); the canvas asks the registry to build each `SceneObject.type`. Kits may register types later; they still do not eval Dart. Unknown type → `UnknownObjectPlaceholder`, not a guessed widget tree. Details: [registry](registry.md).

## Tests at the spine

Every phase ships tests for the seam it introduces (document load/save, mutation, registry lookup, canvas camera, tool dispatch). UI chrome is not a substitute for spine tests. A phase is not done if the new seam can regress silently.

## Docs match code

README, this file, and `docs/` describe what the tree actually does. No APIs, folders, or phases documented as shipped unless they exist. When code moves, docs move in the same change.

## Acceptance before next phase

Do not start phase _n+1_ until phase _n_ meets its acceptance criteria: `flutter analyze` clean, `flutter test` green, and the phase’s stated UX/behavior checks. Phase 8+ is blocked until the current phase gate is green.

## Phase 1 gate — done

- macOS desktop shell launches with branding chrome.
- Folder layout for `app`, `canvas`, `scene`, `registry`, `kit_api`, `agent`, `shared`, `docs`, `kits` exists; later layers stay stubs until their phase.

## Phase 2 gate — done

- Camera is the viewport spine: `CanvasCamera.panScreen` / `zoomAt` / `reset`.
- Screen origin is viewport top-left; world shares those axes; `offset` is the world point at the viewport center; zoom is world-to-screen scale, clamped 0.25–4.0. World `(0,0)` is the **world origin**.

## Phase 3 gate — done

- Scene document in `lib/scene/`. Mutations only via `SceneStore.apply`.
- JSON `schemaVersion` required; unknown fields ignored (tolerant).
- Undo/redo with snapshot strategy; new apply clears redo.
- Persistence: absolute `Application Support/skapie/scene.json` by default (`path_provider`). Overrides: `SKAPIE_SCENE_PATH`, optional project mode with absolute `SKAPIE_PROJECT_ROOT`. Cwd is never the default. One-time migrate from legacy `.skapie/scene.json`. Save errors are logged and stored on the store. Writes `"objects"`; still reads legacy `"nodes"` (`schemaVersion` 1).

## Phase 4 gate — done

- `ObjectRegistry` in `lib/registry/`: `typeId` → builder, default props, display name. Duplicate `typeId` throws.
- Built-ins: `box`, `text`, `button`, plus `debug.rect`. Canvas renders visible objects through the registry (z-sorted). Unknown / failing types → placeholder, never a crash, never Dart eval.
- Thin Add menu inserts via `SceneStore.apply(AddObject)`.

## Phase 5 gate — done

- Single selection is UI state (`SelectionController`). Not persisted.
- Hit-test in the viewport from scene frames (AABB; rotation ignored). Registry widgets stay non-interactive.
- Move: preview in UI; one `UpdateObjectFrame` on pointer-up. Locked: select + delete, no move.
- Thin inspector edits via `UpdateObjectProps` / `UpdateObjectFrame` / `SetObjectLocked`; Delete via `RemoveObject`. Inspector overlays the canvas (does not shrink the viewport). Middle-mouse drag pans without selecting.

## Phase 6 gate — done

- `KitApi` in `lib/kit_api/` wraps `SceneStore.apply` only. Unknown `typeId` rejected. In-memory `registerKit` / `instantiate`; validate-then-apply (no partial spawn).
- Built-in demo recipe `demo.note-card`. Add / inspector / move / delete / lock go through `KitApi`.

## Phase 7 gate (current)

- Kit packages on disk: `kits/<kitId>/kit.json` loaded into `KitApi` at startup (`reloadPackages`). `saveKit` writes pretty JSON.
- Demo `demo.note-card` ships as `kits/demo.note-card/`. Disk replaces in-memory for the same id. Unknown `typeId` in a package skips that package. No Dart eval.
- `capabilities: []` is a seam only; non-empty logs a warning and still loads `objects`. No workers, sandbox, agent, or file watcher.
- `flutter analyze` clean; `flutter test` covers package parse/load/save/conflict + existing spine tests.

Phase 8+ stays blocked until this gate is green. Do not implement sandboxed workers or the agent here.

## Dream goal (not scheduled)

Visible sub-agent kits: a future direction where a kit can show living agent work on the canvas (status, tokens, input/output). That implies sandboxed kit runtimes and permissions later. **Not Phase 7.** Phase 7 only ships declarative on-disk recipes. Planted seam: `capabilities: []` in `kit.json`.
