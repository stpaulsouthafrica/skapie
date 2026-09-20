# Scene document

The scene document is the source of truth for what exists in the world. The canvas camera shows the world; it does not own widget state.

Scene items are **scene objects**. **Graph node** is reserved for a future cable/port graph and is not used here. See [glossary](glossary.md).

## World origin

World `(0,0)` is the **world origin** (also `origin`). It is not “screen center.”

The camera `offset` is the **world point at the viewport center**. A default camera (`offset = (0,0)`, `zoom = 1`) happens to place the world origin at the viewport center, but those are different concepts.

Pan is **not** infinite. The canvas hard-clamps `offset` so the viewport center stays inside padded content bounds (v1; no rubber-band). Bounds are the axis-aligned union of visible scene object frames (`x,y,width,height`; rotation is ignored for this clamp). Padding is `max(minWorldPad, viewportWorldSize * contentPadFraction)` per axis (`minWorldPad = 200`, `contentPadFraction = 0.35`). If nothing is visible, fallback bounds are a 2000×2000 box centered on the **world origin**. Clamp does not mutate the scene. After zoom or reset (`0` / `Cmd+0`), offset is clamped again.

## Model

`SceneDocument`

- `id` — stable document id
- `schemaVersion` — currently `1`, required in JSON
- `objects` — ordered list of `SceneObject`
- `camera` — optional last-saved `SceneCameraSnapshot` (`offsetX`, `offsetY`, `zoom`) for reopen comfort. Live pan/zoom still lives on the canvas.

`SceneObject`

- `id`, `type` (string, e.g. `debug.rect` — a debug scene object)
- `x`, `y`, `width`, `height` — world-space frame; `(x, y)` is the top-left of the unrotated box
- `rotation` — radians around the frame center, default `0`
- `zIndex` default `0`, `locked` default `false`, `visible` default `true`
- `props` — `Map<String, Object?>`

JSON parsing is **tolerant of unknown fields** (they are ignored). `schemaVersion` is required. Extra keys on the document or a scene object do not fail load.

**`objects` vs legacy `nodes`:** schema stays at `1`. New writes use `"objects"`. Load prefers `"objects"` if present; otherwise it reads legacy `"nodes"` (Phase 3 files). If both keys exist, `"objects"` wins.

## Mutations

The only way to change document state is `SceneStore.apply(SceneOp op)`.

| Op | Effect |
|---|---|
| `AddObject` | Append a scene object (no-op if id exists) |
| `RemoveObject` | Drop a scene object by id (no-op if missing) |
| `UpdateObjectFrame` | Patch any of x/y/width/height/rotation |
| `UpdateObjectProps` | **Shallow merge.** Listed keys overwrite; other keys stay. A `null` value **removes** that key. |
| `SetObjectLocked` | Set `SceneObject.locked` (not a prop). No-op if missing id or unchanged. |

Each successful apply snapshots the previous document for undo, clears redo, notifies listeners, and writes the file when persistence is attached. Undo/redo restore those snapshots. A new apply after undo clears the redo stack.

Live camera notes (`SceneStore.noteCamera`) are not undoable scene ops.

## File location

Default (canonical): **`<Application Support>/skapie/scene.json`**, resolved via `path_provider` (`getApplicationSupportDirectory()`). This is an absolute path, not process cwd. On a sandboxed macOS debug run that is typically under the app container’s Application Support, **not** `~/Library/Containers/.../Data/.skapie/` and **not** the git repo.

Startup logs `Skapie scene file: <absolute path>`. The top bar shows a short label (`App Support`, `.skapie/scene.json`, or the last two path segments). Hover or **Copy path** for the absolute path. Save failures are logged and shown there; they are not swallowed.

**Overrides (first match wins):**

1. `--dart-define=SKAPIE_SCENE_PATH=/absolute/file.json`
2. Environment `SKAPIE_SCENE_PATH` (absolute)
3. `--dart-define=SKAPIE_USE_PROJECT_SCENE=true` with `--dart-define=SKAPIE_PROJECT_ROOT=/absolute/repo` (or env `SKAPIE_PROJECT_ROOT`) → `<repo>/.skapie/scene.json`. If project mode is on but the root is missing or not absolute, Skapie **falls back to Application Support** and logs a warning. It does not guess cwd.
4. Otherwise Application Support as above.

Relative override paths are rejected (warning + Application Support). `.skapie/` is gitignored so project-local files are never committed.

**One-time migration:** if the canonical file does not exist, Skapie copies `Directory.current/.skapie/scene.json` (the old cwd-relative / container Data path) into the canonical location when that legacy file exists. A known macOS container path (`~/Library/Containers/com.skapie.skapie/Data/.skapie/scene.json`) is also checked. After a successful copy, that canonical file is the source of truth.

Missing canonical file (and no legacy to migrate) → empty document, no throw. Parent directories are created on first save.

Files write `"objects"`; older files with `"nodes"` still load (`schemaVersion` 1).

## Rendering

The canvas does not own widget trees. `SceneObjectLayer` lists `store.document.objects`, sorts by `zIndex`, and asks `ObjectRegistry.build` for each visible object. Frames still come from world `x` / `y` / `width` / `height`. Unknown types show a placeholder. See [registry](registry.md).

Selection, move, and inspector edits are UI; they call `SceneStore.apply` and do not persist `selectedId`. Hit-test ignores rotation. See [interaction](interaction.md).
