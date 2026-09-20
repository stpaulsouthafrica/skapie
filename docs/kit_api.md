# Kit API

`KitApi` is the **only high-level way** to change the scene. It does not own a parallel object list. Every method wraps `SceneStore.apply(SceneOp)`.

It is **not** a disk loader. Kit packages under `kits/` are Phase 7. The agent harness is Phase 9.

A **kit** is an in-memory recipe you can instantiate. A **kit package** is an on-disk folder (not loaded here). Instantiating a kit creates **scene objects**. See [glossary](glossary.md).

Registrations live in process memory. Restarting the app drops custom `registerKit` calls unless code registers them again (the demo recipe is registered at startup).

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

`instantiate` of N objects is N `apply` calls = **N undo steps** (v1).

## Demo recipe

`demo.note-card` is registered by `createAppKitApi` at startup: a `box` with a `text` inset (`content`: `Note`). Add menu: **Demo kit: note card**. Origin is the camera offset (world point at viewport center).

## Not this phase

- Reading/writing `kits/<id>/`
- Agent tools
- Batched multi-object undo
