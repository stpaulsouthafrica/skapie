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

Each successful apply snapshots the previous document for undo, clears redo, notifies listeners, and writes the file when persistence is attached. Undo/redo restore those snapshots. A new apply after undo clears the redo stack.

Live camera notes (`SceneStore.noteCamera`) are not undoable scene ops.

## File location

Default path: **`.skapie/scene.json`** relative to the process working directory (the repo root when you `flutter run` from this project). Missing file → empty document. The directory is gitignored.

## Debug draw

Phase 3 draws every visible scene object as a gray rectangle from its frame. This is temporary and is **not** a registry. Unknown `type` strings still draw as that debug rect.
