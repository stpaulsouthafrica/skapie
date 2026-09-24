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
| **Harness kit** | A kit that is part of the agent harness on the world: LLM, system prompt, or tools. Still ordinary scene objects via a kit recipe. Not a second scene system. |
| **LLM kit** | `harness.llm`. Specialized compound kit: panel card, accent hairline, title-bar chrome, per-kit model, Needs input, Input, Context, Conversation, Tools, and Output. Those rows are port labels. Ports that accept more than one cable show a connection count. A status line shows Ready, Running, Waiting for review, Completed, Failed, or Cancelled. The reply is written into text kits cabled from Output. Frame and body move and delete together. Attach `tools.*` grants via `attachedTo`. |
| **Conversation kit** | `harness.conversation`. The earlier user and assistant turns for an LLM. Cable its output into the Conversation port. A successful run appends that turn. |
| **Principle kit** | Dumb data/structure on the board (Note, System prompt, Tools, Input as a region). Holds text. Does not run a network. |
| **Specialized kit** | Irreducible behavior. Today: `harness.llm`. |
| **System-prompt kit** | `harness.system-prompt`. Stub: editable prompt text on the board. Not injected into first Enter. |
| **Tools kit** | `harness.tools`. Stub: tools as a separate concern from the model. Not attached to first Enter. |
| **Agent session** | In-memory message log + turn/tool loop. Kept for a later board wire. Not the default chat Enter. See [agent](agent.md). |
| **Full Screen text editor** | The one global full-screen window for reading or editing text (`showFullScreenTextEditor` in `lib/app/full_screen_text_editor.dart`). Double-clicking a text kit opens it to edit. The run evidence magnifying glass and the Request Information view open it read-only. It numbers every line, lights only the hovered or edited line number, and picks JSON, Dart, or plain text coloring from the content. Every full-screen text view uses this editor. Do not build another. |
| **Paint** | Cosmetic chrome only: tokens and transient settings. Not the scene, not a kit. See [paint](paint.md). |
| **Graph node** | Reserved for a future cable/port graph. **Do not use for scene items.** |

Do not use bare “recipe” in docs/UI. Say **kit recipe** or **kit package**.

Scene items are **scene objects**. A **graph node** is something else and is not implemented yet.
