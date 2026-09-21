# Skapie

Skapie is a Flutter desktop app: a canvas over an infinite world, a scene document of scene objects, and kits (capability instances; kit packages live on disk under `kits/`). v1 does not generate arbitrary Dart widgets at runtime: an agent will edit scene data, and a registry renders known types.

This repository is **Phase 10.3.1** — vanilla first Enter on OpenCode Go completions / responses / messages, with a curated providers catalog. Streaming, Pi/MCP, sandbox kits, and living sub-agent kits are later arcs.

## Run on macOS

Requires [Flutter](https://docs.flutter.dev/get-started/install) with desktop enabled.

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter run -d macos
```

You should get a window titled **Skapie Canvas** with a thin **Skapie** bar and a canvas that fills the rest of the window.

**Pan:** drag the empty canvas, or two-finger trackpad pan. Pan is hard-clamped so the viewport center stays in padded content bounds (empty scene: 2000×2000 around the world origin). **Zoom:** mouse wheel or trackpad pinch; zoom is anchored to the pointer, not the viewport center. After zoom, offset is re-clamped. **Reset:** `0` or `Cmd+0` (also `Ctrl+0` / numpad `0`) restores zoom `100%` and recenters on the **world origin**, then clamps. Zoom is clamped to 25%–400%. A zoom percentage HUD sits in the corner; a dot grid and origin cross mark world `(0,0)`.

**Scene (dev):** **Add** → Box / Text / Button / Debug rect / **Demo kit: note card**. Adds go through `KitApi` (which calls `SceneStore.apply`). Click an object to select it (outline + inspector). Drag a selected unlocked object to move it. Click empty canvas to pan and clear selection. Delete/Backspace removes the selected object when the canvas is focused. Press `N` for a `debug.rect`. `Cmd+Z` / `Cmd+Shift+Z` undo/redo. Selection is not saved.

**Transforms:** screen origin is the viewport top-left (Flutter: +x right, +y down). World uses the same axes. World `(0,0)` is the **world origin**. The camera `offset` is the world point shown at the viewport center — not another name for the origin.

**Save file:** absolute path under Application Support (`…/skapie/scene.json`) by default. Logged at startup. The top bar shows a short label; hover or **Copy path** for the full path. Not cwd-relative unless you explicitly enable project mode with an **absolute** `SKAPIE_PROJECT_ROOT`. See [`docs/scene.md`](docs/scene.md).

**Kits:** declarative packages under `kits/<id>/kit.json`. Startup loads them into `KitApi`. Default kits root is Application Support (`…/skapie/kits`) because a sandboxed macOS app cannot see the git repo. Point at the repo shelf with an **absolute** override:

```bash
# default: Application Support
flutter run -d macos

# developer: repo-local scene (absolute root required)
flutter run -d macos \
  --dart-define=SKAPIE_USE_PROJECT_SCENE=true \
  --dart-define=SKAPIE_PROJECT_ROOT=/Users/you/Development/skapie

# developer: load repo kit packages (absolute root required)
flutter run -d macos \
  --dart-define=SKAPIE_PROJECT_ROOT=/Users/you/Development/skapie
# or: --dart-define=SKAPIE_KITS_ROOT=/Users/you/Development/skapie/kits
```

**Agent:** A capsule chat strip at the bottom (about one third of the window) is an on-ramp. Enter sends vanilla user text only. OpenCode Go models are routed from the curated catalog (`lib/providers/opencode_go/`) to `/chat/completions`, `/responses`, or `/messages`. The latest turn shows on the `harness.llm` kit. System prompt and tools are separate stub kits you can add to the board; they do not silently attach to first Enter. `/settings` or Cmd+, opens Connect → models → Apply. **Use Fake** switches back without a restart. No key → Fake Echo. Keys are never committed and never written into the scene file. Provider/model/thinking/key persist in Application Support `skapie/agent_prefs.json`. See [`docs/providers.md`](docs/providers.md).

```bash
# OpenCode Go (preferred for local testing)
flutter run -d macos \
  --dart-define=SKAPIE_AGENT_PROVIDER=opencode-go \
  --dart-define=SKAPIE_AGENT_API_KEY="$OPENCODE_API_KEY" \
  --dart-define=SKAPIE_AGENT_MODEL=kimi-k2.6

# OpenRouter
flutter run -d macos \
  --dart-define=SKAPIE_AGENT_PROVIDER=openrouter \
  --dart-define=SKAPIE_AGENT_API_KEY="$OPENROUTER_API_KEY" \
  --dart-define=SKAPIE_AGENT_MODEL=anthropic/claude-sonnet-4

# Or export OPENCODE_API_KEY / OPENROUTER_API_KEY and only pass provider + model.
# Or run with no key: Chat → gear → paste → Connect → pick model → Apply.
```

Suggested model ids are examples (`kimi-k2.6`, `anthropic/claude-sonnet-4`, `gpt-4o-mini`). See [`docs/agent.md`](docs/agent.md).

## Foundation gates

Skapie is built phase by phase. **The 10-phase core is complete.** Phase 10.1 is post-core settings UX. Later arcs stay out of scope. Doctrine lives in [`docs/foundation.md`](docs/foundation.md). Scene details are in [`docs/scene.md`](docs/scene.md). Registry details are in [`docs/registry.md`](docs/registry.md). Interaction is in [`docs/interaction.md`](docs/interaction.md). Kit API reference is in [`docs/kit_api.md`](docs/kit_api.md). Kit packages are in [`docs/kit_packages.md`](docs/kit_packages.md). Agent harness is in [`docs/agent.md`](docs/agent.md). Vocabulary is in [`docs/glossary.md`](docs/glossary.md).

**Phase 1 gate:** macOS shell + folder stubs — done.

**Phase 2 gate:** infinite canvas pan/zoom + tested transforms — done.

**Phase 3 gate:** scene model + `SceneStore.apply` + undo/redo + JSON round-trip + `.skapie/scene.json` — done.

**Phase 4 gate:** `ObjectRegistry` maps `type` → builder; built-ins `box` / `text` / `button` / `debug.rect`; unknown types placeholder; Add menu via `apply` — done.

**Phase 5 gate:** single select + move (one undo) + overlay inspector (`SetObjectLocked`, no canvas reflow) + MMB pan; selection not in `scene.json` — done.

**Phase 6 gate:** `KitApi` wraps `SceneStore.apply`; in-memory kit recipes + demo note card — done.

**Phase 7 gate:** on-disk `kits/<id>/kit.json` loaded into `KitApi`; `saveKit` / `reloadPackages`; disk replaces memory; no sandbox — done.

**Phase 8 gate:** complete Kit API docs (methods, cookbook, package paths, unimplemented agent-tool sketch) — done.

**Phase 9 gate:** `AgentSession` + `FakeAgentModel` — done.

**Phase 9.1 gate:** kit tools → `KitApi`; scripted tool loop — done.

**Phase 9.2 gate:** OpenAI-compatible provider + presets + overlay chat; Fake fallback — done.

**Phase 10 gate:** agent settings, session rebuild, prefs (no key on disk), Fake/live chip, empty state — **10-phase core complete**.

**Phase 10.1 gate:** Connect → fetch `/models` → pick; Thinking when the catalog lists efforts; no typed model/base URL.

**Phase 10.2.1 gate:** world-as-harness; vanilla first Enter; LLM / system-prompt / tools kits.

**Phase 10.3.1 gate:** OpenCode Go seating chart in `lib/providers/`; completions / responses / messages vanilla routing.

## Docs

- [`docs/glossary.md`](docs/glossary.md) — canvas, world origin, scene object, kit, kit recipe, kit package, graph node
- [`docs/foundation.md`](docs/foundation.md) — doctrine and phase gates
- [`docs/scene.md`](docs/scene.md) — document model, ops, file path, world origin
- [`docs/registry.md`](docs/registry.md) — type string → builder, unknown placeholder
- [`docs/interaction.md`](docs/interaction.md) — select, move, inspector
- [`docs/kit_api.md`](docs/kit_api.md) — Kit API reference, cookbook, agent tools
- [`docs/kit_packages.md`](docs/kit_packages.md) — folder contract, `kit.json`, kits root
- [`docs/agent.md`](docs/agent.md) — session, vanilla first Enter, harness kits, Connect → models
- [`docs/providers.md`](docs/providers.md) — OpenCode Go seating chart and surfaces
- [`docs/paint.md`](docs/paint.md) — cosmetic identity: tokens, transient settings
- **Dream goal / later arcs (not scheduled):** visible sub-agent kits, sandbox, personal coding-agent kit — the 10-phase core is not that
