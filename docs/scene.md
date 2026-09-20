# Scene document

The scene document is the source of truth for what exists in the world. The canvas camera shows the world; it does not own widget state.

## World origin

World `(0,0)` is the **world origin** (also `origin`). It is not “screen center.”

The camera `offset` is the **world point at the viewport center**. A default camera (`offset = (0,0)`, `zoom = 1`) happens to place the world origin at the viewport center, but those are different concepts.

## Model

`SceneDocument`

- `id` — stable document id
- `schemaVersion` — currently `1`, required in JSON
- `nodes` — ordered list of `SceneNode`
- `camera` — optional last-saved `SceneCameraSnapshot` (`offsetX`, `offsetY`, `zoom`) for reopen comfort. Live pan/zoom still lives on the viewport.

`SceneNode`

- `id`, `type` (string, e.g. `debug.rect`)
- `x`, `y`, `width`, `height` — world-space frame; `(x, y)` is the top-left of the unrotated box
- `rotation` — radians around the frame center, default `0`
- `zIndex` default `0`, `locked` default `false`, `visible` default `true`
- `props` — `Map<String, Object?>`

JSON parsing is **tolerant of unknown fields** (they are ignored). `schemaVersion` is required. Extra keys on the document or a node do not fail load.

## Mutations

The only way to change document state is `SceneStore.apply(SceneOp op)`.

| Op | Effect |
|---|---|
| `AddNode` | Append a node (no-op if id exists) |
| `RemoveNode` | Drop a node by id (no-op if missing) |
| `UpdateNodeFrame` | Patch any of x/y/width/height/rotation |
| `UpdateNodeProps` | **Shallow merge.** Listed keys overwrite; other keys stay. A `null` value **removes** that key. |

Each successful apply snapshots the previous document for undo, clears redo, notifies listeners, and writes the file when persistence is attached. Undo/redo restore those snapshots. A new apply after undo clears the redo stack.

Live camera notes (`SceneStore.noteCamera`) are not undoable scene ops.

## File location

Default path: **`.skapie/scene.json`** relative to the process working directory (the repo root when you `flutter run` from this project). Missing file → empty document. The directory is gitignored.

## Debug draw

Phase 3 draws every visible node as a gray rectangle from its frame. This is temporary and is **not** a registry. Unknown `type` strings still draw as that debug rect.
