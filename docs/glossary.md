# Glossary

Locked product vocabulary. Use these words in code, comments, docs, and UI.

| Term | Meaning |
|---|---|
| **Canvas** | Viewport / glass. Pan + zoom live here. |
| **World** | Infinite space behind the canvas. |
| **World origin** / **origin** | World `(0,0)`. Not “screen center.” |
| **Scene** | Save-file source of truth of what exists. |
| **Scene object** | One typed item in the scene (`id`, `type`, frame, `props`). |
| **Kit** | Capability you can instantiate into the world. Not “plugin.” Not a Pi “extension.” In code, a loaded kit is a `KitRecipe` in `KitApi`. See [kit API](kit_api.md). |
| **Kit recipe** (`KitRecipe`) | In-memory definition: `id`, `displayName`, relative `KitObjectSpec`s. This is what `registerKit`, `getKit`, `listKits`, `instantiate`, and `saveKit` use. |
| **Kit package** | On-disk folder `kits/<id>/` with `kit.json`. Loading a package creates/updates a kit recipe in memory. Instantiating never reads the folder mid-turn; it uses the in-memory kit recipe. See [kit packages](kit_packages.md). |
| **Agent session** | In-memory message log + turn/tool loop. Not the scene. Not a kit. See [agent](agent.md). |
| **Paint** | Cosmetic chrome only: tokens and transient settings. Not the scene, not a kit. See [paint](paint.md). |
| **Graph node** | Reserved for a future cable/port graph. **Do not use for scene items.** |

Do not use bare “recipe” in docs/UI. Say **kit recipe** or **kit package**.

Scene items are **scene objects**. A **graph node** is something else and is not implemented yet.
