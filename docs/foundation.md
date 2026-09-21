# Skapie foundation doctrine

These rules bind every phase. If a change fights them, the change is wrong.

## One mutation path

Scene data changes only through `SceneStore.apply(SceneOp)`. Widgets, kits, and the agent must not poke document fields. The Kit API wraps these ops; it does not bypass them. Live camera pan/zoom is canvas state; `noteCamera` only snapshots it for save.

## Scene is the source of truth

The scene document is what is real. The canvas, inspector, and any agent memory are views or proposals. Reload from scene and the UI must reconstruct. Selection (`selectedId`) is **UI state only** — not a scene field and not persisted. Camera pan limits read those objects and clamp viewport state only — they never mutate the scene.

Vocabulary: scene items are **scene objects**. **Graph node** is reserved for a future cable/port graph. Full table: [glossary](glossary.md).

## Registry over fantasy

v1 does not generate arbitrary Dart widgets at runtime. Known types live in `ObjectRegistry` (`lib/registry/`); the canvas asks the registry to build each `SceneObject.type`. Kits may register types later; they still do not eval Dart. Unknown type → `UnknownObjectPlaceholder`, not a guessed widget tree. Details: [registry](registry.md).

## Tests at the spine

Every phase ships tests for the seam it introduces (document load/save, mutation, registry lookup, canvas camera, tool dispatch). UI chrome is not a substitute for spine tests. A phase is not done if the new seam can regress silently.

## Docs match code

README, this file, and `docs/` describe what the tree actually does. No APIs, folders, or phases documented as shipped unless they exist. When code moves, docs move in the same change.

## Acceptance before next phase

Do not start phase _n+1_ until phase _n_ meets its acceptance criteria: `flutter analyze` clean, `flutter test` green, and the phase’s stated UX/behavior checks. The 10-phase core completed at Phase 10. **10.1** is post-core settings UX (Connect → fetch models). **10.2** is cosmetic paint only. **10.2.1** is harness-as-kits. **10.3.1** is the OpenCode Go providers catalog and three vanilla surfaces.

## Phase 1 gate — done

- macOS desktop shell launches with branding chrome.
- Folder layout for `app`, `canvas`, `scene`, `registry`, `kit_api`, `agent`, `shared`, `docs`, `kits` exists; later layers stay stubs until their phase.

## Phase 2 gate — done

- Camera is the viewport spine: `CanvasCamera.panScreen` / `zoomAt` / `reset`.
- Screen origin is viewport top-left; world shares those axes; `offset` is the world point at the viewport center; zoom is world-to-screen scale, clamped 0.25–4.0. World `(0,0)` is the **world origin**.

## Phase 3 gate — done

- Scene document in `lib/scene/`. Mutations only via `SceneStore.apply`.
- JSON `schemaVersion` required; unknown fields ignored (tolerant).
- Undo/redo with snapshot strategy; new apply clears redo.
- Persistence: absolute `Application Support/skapie/scene.json` by default (`path_provider`). Overrides: `SKAPIE_SCENE_PATH`, optional project mode with absolute `SKAPIE_PROJECT_ROOT`. Cwd is never the default. One-time migrate from legacy `.skapie/scene.json`. Save errors are logged and stored on the store. Writes `"objects"`; still reads legacy `"nodes"` (`schemaVersion` 1).

## Phase 4 gate — done

- `ObjectRegistry` in `lib/registry/`: `typeId` → builder, default props, display name. Duplicate `typeId` throws.
- Built-ins: `box`, `text`, `button`, plus `debug.rect`. Canvas renders visible objects through the registry (z-sorted). Unknown / failing types → placeholder, never a crash, never Dart eval.
- Thin Add menu inserts via `SceneStore.apply(AddObject)`.

## Phase 5 gate — done

- Single selection is UI state (`SelectionController`). Not persisted.
- Hit-test in the viewport from scene frames (AABB; rotation ignored). Registry widgets stay non-interactive.
- Move: preview in UI; one `UpdateObjectFrame` on pointer-up. Locked: select + delete, no move.
- Thin inspector edits via `UpdateObjectProps` / `UpdateObjectFrame` / `SetObjectLocked`; Delete via `RemoveObject`. Inspector overlays the canvas (does not shrink the viewport). Middle-mouse drag pans without selecting.

## Phase 6 gate — done

- `KitApi` in `lib/kit_api/` wraps `SceneStore.apply` only. Unknown `typeId` rejected. In-memory `registerKit` / `instantiate`; validate-then-apply (no partial spawn).
- Built-in demo kit `demo.note-card` (kit recipe in memory). Add / inspector / move / delete / lock go through `KitApi`.

## Phase 7 gate — done

- Kit packages on disk: `kits/<kitId>/kit.json` loaded into `KitApi` at startup (`reloadPackages`). `saveKit` writes pretty JSON.
- Demo `demo.note-card` ships as `kits/demo.note-card/`. Disk replaces the in-memory kit recipe for the same id. Unknown `typeId` in a package skips that package. No Dart eval.
- `capabilities: []` is a seam only; non-empty logs a warning and still loads `objects`. No workers, sandbox, agent, or file watcher.

## Phase 8 gate — done

- Complete Kit API documentation: mental model, every public `KitApi` method, cookbook, package contract linked from [kit packages](kit_packages.md), agent-tool sketch labeled **not implemented**.
- Docs match `lib/kit_api/kit_api.dart`. Kits root (repo vs Application Support vs override) is unambiguous.

## Phase 9 gate — done

- Agent harness core in `lib/agent/`: `AgentSession`, `AgentModel`, `FakeAgentModel`, events. One turn: user → model → assistant. No HTTP.

## Phase 9.1 gate — done

- Kit tools dispatch to `KitApi` only (`add_object` → `addObject`, …). Tool results are `AgentRole.tool` messages. Loop until plain text or max 8 iterations.
- `ScriptedAgentModel` for tests. Unknown tool / unknown `typeId` → tool error JSON, scene unchanged.
- No chat UI, no HTTP in 9.1.

## Phase 9.2 gate — done

- `OpenAiCompatibleAgentModel` POST `{baseUrl}/chat/completions`; inject `http.Client` in tests.
- Named presets `opencode-go`, `openrouter`, `openai`, `custom` (one HTTP client). Missing key/model → `FakeAgentModel`.
- Overlay chat is an on-ramp. Vanilla first Enter; failures land on `harness.llm`.

## Phase 10 gate — done

- Agent settings (gear on chat): provider, model, API key. Apply rebuilds `AgentSession` on the same `KitApi` (system prompt kept; prior turns cleared). Use Fake one-click.
- Prefs at Application Support `skapie/agent_prefs.json` restore provider, model, and key. Never in `scene.json`.
- Chat chip Fake vs `{preset} · {model}`; empty-state suggested prompts. Overlay still does not reflow the canvas.

The **10-phase core is complete.** Later arcs (streaming, Pi/MCP, sandbox kits, visible sub-agent kits, personal coding-agent kit) stay out of scope.

## Phase 10.1 gate — done

- Settings UX: provider → paste key → **Connect** → `GET /models` → Model dropdown. No typed model id. No Base URL field. `custom` not in the panel.
- Thinking row only when the catalog lists efforts. OpenRouter `reasoning.effort` on chat completions; OpenCode Go / OpenAI thinking is UI-reserved / hidden when the catalog has none.
- Prefs schema 2: `provider`, `model`, optional `thinkingLevel`. Optional `apiKey` was added so settings reopen and relaunch keep Connect state (never in `scene.json`). No base URL written from the UI.
- `flutter analyze` clean; `flutter test` covers catalog parse, Connect mock HTTP, prefs, session swap, and Fake Echo chat.

## Phase 10.2 gate — done

- Cosmetic only. `lib/paint/` holds tokens, chrome widgets, and a theme bridge. App imports paint. Paint does not own scene, kits, or the agent loop.
- Fixed dark + champagne gold. No appearance prefs. No glass window or transparency slider. The macOS window is opaque.
- Chat is a thin bar over the bottom third. Settings open from `/settings` and Cmd+, as a transient sheet. Inspector stays an overlay.
- Engine seams (Kit API, scene schema, registry, tool loop) unchanged.

## Phase 10.2.1 gate — done

- Thesis: the world is the harness. The bottom chat bar is an on-ramp, not a hidden full agent stack.
- Prefs: `provider`, `model`, optional `thinkingLevel`, optional `apiKey`. File is Application Support `skapie/agent_prefs.json`. Cold start rebuilds live pipe when key+model resolve. **Never** write the key into `scene.json`. No Keychain.
- First Enter is vanilla user text only. No tools. No Skapie system prompt. No reasoning.
- `harness.llm` shows the turn (or redacted HTTP error) via `KitApi`. `harness.system-prompt` and `harness.tools` are real stub kit packages; they do not re-fat the vanilla payload. Reserved `attachedTo` seam only.
- `AgentSession` tool loop is kept but is not the default first Enter.
- `flutter analyze` clean; `flutter test` green. No animations.

## Phase 10.3.1 gate (current)

- Curated providers catalog in `lib/providers/`. OpenCode Go seating chart: [`lib/providers/opencode_go/opencode_go_catalog.json`](../lib/providers/opencode_go/opencode_go_catalog.json). How-to: [providers](providers.md).
- Connect joins live `GET /models` with the chart. Unknown live ids are unverified (not silently completions). Chart-only ids missing from live are omitted.
- Vanilla first Enter routes `switch (surface)`: completions `/chat/completions`, responses `/responses`, messages `/messages`. User text only on all three.
- LLM kit diagnostics include provider, model, surface, URL, status, body. Never the API key.
- `flutter analyze` clean; `flutter test` green.

## Dream goal (not scheduled)

Visible sub-agent kits: a future direction where a kit can show living agent work on the canvas (status, tokens, input/output). That implies sandboxed kit runtimes and permissions later. The 10-phase core (session + kit tools + overlay chat + settings) is **not** that. Planted seam: `capabilities: []` in `kit.json`.
