# Glossary

Locked product vocabulary. Use these words in code, comments, docs, and UI.

| Term | Meaning |
|---|---|
| **Canvas** | Viewport / glass. Pan + zoom live here. |
| **World** | Infinite space behind the canvas. |
| **World origin** / **origin** | World `(0,0)`. Not “screen center.” |
| **Scene** | Save-file source of truth of what exists. |
| **Scene object** | One typed item in the scene (`id`, `type`, frame, `props`). |
| **Kit** | Capability / tool instance in the user’s world. Not “plugin.” Not a Pi “extension.” |
| **Kit package** | On-disk recipe folder under `kits/`. |
| **Graph node** | Reserved for a future cable/port graph. **Do not use for scene items.** |

Scene items are **scene objects**. A **graph node** is something else and is not implemented yet.
