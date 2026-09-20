# Kit API

`KitApi` is the **only high-level way** to change the scene. It does not own a parallel object list. Every method wraps `SceneStore.apply(SceneOp)`.

A **kit** is a `KitRecipe` you can instantiate into **scene objects**. A **kit package** is the on-disk folder under `kits/` (`kit.json`). Disk load/save is documented in [kit packages](kit_packages.md). The agent harness is still later.

`registerKit` is ephemeral in-memory. **Saved** packages are the durable shelf. On `reloadPackages`, **disk replaces memory** for the same id.

## Surface

| Method | Effect |
|---|---|
| `addObject(typeId, …)` | Registry defaults + size map; `AddObject`; returns new id. Unknown `typeId` → `ArgumentError`, scene unchanged. |
| `removeObject(id)` | `RemoveObject` |
| `updateFrame(…)` | `UpdateObjectFrame` |
| `updateProps(id, patch)` | `UpdateObjectProps` |
| `setLocked(id, locked)` | `SetObjectLocked` |
| `registerKit(recipe)` | In-memory only. Duplicate kit id → `StateError`. |
| `getKit` / `listKits` | Lookup |
| `instantiate(kitId, origin:)` | Validate all spec `typeId`s first, then add each object. Relative `x,y` + `origin`. Unknown type → `ArgumentError`, **no partial spawn**. |
| `reloadPackages()` | Scan the kits root; register each package. Disk replaces in-memory for the same id. |
| `saveKit(recipe)` | Write `kits/<id>/kit.json` (pretty JSON), then register/update in memory. |

`instantiate` of N objects is N `apply` calls = **N undo steps** (v1).

`createAppKitApi` registers the in-memory `demo.note-card` fallback, then app bootstrap calls `reloadPackages()` so a disk package wins when present.

## Demo recipe

`demo.note-card` ships as `kits/demo.note-card/kit.json`: a `box` with a `text` inset (`content`: `Note`). Add menu lists kits from `listKits()` (**Demo kit: note card** for the demo id). Origin is the camera offset (world point at viewport center).

## Not this phase

- Executing `capabilities` / sandboxed workers
- Agent tools
- Batched multi-object undo
- Save-selection UI
