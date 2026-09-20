# Skapie foundation doctrine

These rules bind every phase. If a change fights them, the change is wrong.

## One mutation path

Scene data changes through a single, explicit path (tools, commands, or a documented editor API). Widgets, kits, and the agent do not poke document state on the side. If two writers can update the same field, the design has failed.

## Scene is the source of truth

The scene document is what is real. The canvas, inspector, and any agent memory are views or proposals. Reload from scene and the UI must reconstruct. Do not store lasting product state only in widget state, canvas controllers, or chat transcripts.

## Registry over fantasy

v1 does not generate arbitrary Dart widgets at runtime. Known types live in a registry; kits register types; the renderer draws only what the registry knows. Unknown type → explicit fallback, not a guessed widget tree.

## Tests at the spine

Every phase ships tests for the seam it introduces (document load/save, mutation, registry lookup, canvas camera, tool dispatch). UI chrome is not a substitute for spine tests. A phase is not done if the new seam can regress silently.

## Docs match code

README, this file, and `docs/` describe what the tree actually does. No APIs, folders, or phases documented as shipped unless they exist. When code moves, docs move in the same change.

## Acceptance before next phase

Do not start phase _n+1_ until phase _n_ meets its acceptance criteria: `flutter analyze` clean, `flutter test` green, and the phase’s stated UX/behavior checks. Phase 2+ is blocked until the current phase gate is green.

## Phase 1 gate — done

- macOS desktop shell launches with branding chrome.
- Folder layout for `app`, `canvas`, `scene`, `registry`, `kit_api`, `agent`, `shared`, `docs`, `kits` exists; later layers stay stubs until their phase.

## Phase 2 gate (current)

- Camera is the spine for this phase: one mutation path (`CanvasCamera.panScreen` / `zoomAt` / `reset`). There is still no scene document and no Kit API.
- Screen origin is viewport top-left; world shares those axes; `offset` is the world point at the viewport center; zoom is world-to-screen scale, clamped 0.25–4.0.
- `flutter analyze` has no issues; `flutter test` covers transform round-trip, zoom clamp, zoom-at-point, viewport HUD, and the smoke test.
- README describes pan/zoom, reset, and the transform convention.

Phase 3+ stays blocked until this gate is green. Do not implement scene nodes, registry widgets, kits, or the agent here.
