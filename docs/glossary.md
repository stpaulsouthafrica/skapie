# Glossary

Locked product vocabulary. Use these words in code, comments, docs, and UI.

| Term | Meaning |
|---|---|
| **Canvas** | Viewport / glass. Pan + zoom live here. |
| **World** | Infinite space behind the canvas. |
| **World origin** / **origin** | World `(0,0)`. Not “screen center.” |
| **Scene** | Save-file source of truth of what exists. |
| **Scene object** | One typed item in the scene (`id`, `type`, frame, `props`). |
| **Kit** | Capability / recipe you can instantiate into the world. Not “plugin.” Not a Pi “extension.” See [kit API](kit_api.md). |
| **Kit package** | On-disk recipe folder under `kits/`. See [kit packages](kit_packages.md). |
| **Agent session** | In-memory message log + turn loop. Not the scene. Not a kit. See [agent](agent.md). |
| **Graph node** | Reserved for a future cable/port graph. **Do not use for scene items.** |

Scene items are **scene objects**. A **graph node** is something else and is not implemented yet.
