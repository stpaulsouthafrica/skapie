# Agent harness

The **world is the harness.** There is no persistent chat bar. Authoring is:

1. **Space / F3 command palette** to search and add primitives and kits, or open Settings.
2. **Selection typing** on a compound LLM kit: keystrokes edit that kit’s prompt; Enter runs vanilla onto that kit.

**Principle kits** are dumb data/structure (Note, System prompt, Tools, and the LLM kit’s Input region). **Specialized kits** have irreducible behavior. `harness.llm` is specialized: title-bar chrome, per-kit model, Needs input, vanilla completion into Output. Frame and body move as one. No cables.

Completions/responses/messages clients live under `lib/providers/`. **System prompt** and **Tools** remain unwired stubs. The tool-loop `AgentSession` stays in `lib/agent/` until a later board wire. Wiring those stubs onto the HTTP payload is later.

The **scene document** remains the source of truth. Mutations go `KitApi` → `SceneStore.apply`. The palette instantiates through KitApi. Selection typing updates prompt through KitApi. `AgentController.sendUser` writes reply/error onto a **targeted** LLM kit body. **Kit** / **kit recipe** / **kit package**: [glossary](glossary.md).

## What this is / isn’t

| Now | Later |
|---|---|
| Palette on-ramp; no global chat strip | Visible plugs / wires |
| Specialized compound LLM kit: icon + per-kit model + Input/Output | Detach Input/Output into kits |
| Vanilla HTTP kernel in `lib/providers/` | Inject system prompt + tools from board kits |
| Agent folder keeps session/tool-loop code | Those capabilities become board kits |

Living sub-agent kits (status, tokens, workers) remain a dream goal. These harness kits are static box + text first principles.

## Mental model

1. Settings supply the **pipe**: provider, base URL, API key, and the Connect catalog. No second credentials store.
2. Palette **Add LLM** places a specialized `harness.llm` via KitApi near the view center.
3. Select that kit. Inspector hosts **model** (catalog from Settings/Connect, or the OpenCode Go chart when nothing is connected) and **Input**. Enter or Run. Vanilla runs for **that kit’s** model/surface onto **Output** (Fake Echo offline). Empty Input shows **Needs input** and does not call the network.
4. `harness.system-prompt` and `harness.tools` can sit on the board. They do **not** change the vanilla payload.
5. With nothing selected as an LLM kit, Space opens the palette. Typing does not talk to a hidden global agent.
6. `AgentSession` is kept for a later wire. Selection Enter does not call `session.sendUser`.

```
palette Add LLM
  → KitApi.instantiate(harness.llm)

select LLM kit, type, Enter
  → updateProps prompt via KitApi
  → controller.sendUser(text, targetBodyId: body.id)
       Fake: reply = "Echo: …"
       else vanilla surface client (completions / responses / messages)
  → publishLlmKit onto that body
```

Later (not this phase) a wired harness could become:

```
session.sendUser(...)
  → system message from a system-prompt kit
  → tools from a tools kit
  → tool loop → KitApi
```

Default system prompt (`defaultAgentSystemPrompt`) still seeds **AgentSession** only. It is not in the vanilla payload.

## Public surface

| Type | Role |
|---|---|
| `VanillaCompletionClient` | `lib/providers/vanilla_completion.dart`. Plain POST `/chat/completions`. |
| `VanillaResponsesClient` | `lib/providers/vanilla_responses.dart`. Plain POST `/responses`. `{ model, input }`. |
| `VanillaMessagesClient` | `lib/providers/vanilla_messages.dart`. Plain POST `/messages`. `{ model, max_tokens, messages: [user] }`. |
| `UnverifiedVanillaClient` | Live id not in the chart. Throws; does not POST completions. |
| `AgentHttpException` | Non-2xx / timeout. Carries `statusCode` + `body` when HTTP. |
| `AgentHttpDiagnostic` | Redacted request summary (provider, model, surface, URL, status, body). Never the API key. |
| `publishLlmKit` | Updates the selected compound LLM kit body (Input/Output) through `KitApi`. Does not instantiate. |
| `AgentController.sendUser` | Vanilla onto a targeted LLM kit body. No body id → no-op. |
| `AgentSession` | Later tool-loop harness. Not the default first Enter. |
| `OpenAiCompatibleAgentModel` | Session HTTP model (tools + optional OpenRouter reasoning) |
| `FakeAgentModel` | `Echo: <last user text>` for session tests |
| `AgentPrefs` / `AgentPrefsStore` | Application Support prefs (optional local `apiKey`) |
| `createWorldTools` / `createKitAgentTools` | World tool list. Per-file runners in `lib/tools/world/`. Session default is the full list; LLM Enter uses attached grants only. |

## Provider presets

One HTTP client. A const table fills base URL, key env, and optional headers.

| Preset id | Default base URL | Key env (also dart-define twin) | Extra headers |
|---|---|---|---|
| `opencode-go` | `https://opencode.ai/zen/go/v1` | `OPENCODE_API_KEY` / `SKAPIE_AGENT_API_KEY` | `x-opencode-session: <session id>`, `User-Agent: skapie/0.1` |
| `openrouter` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` / `SKAPIE_AGENT_API_KEY` | `HTTP-Referer: https://skapie.local`, `X-Title: Skapie` |
| `openai` | `https://api.openai.com/v1` | `OPENAI_API_KEY` / `SKAPIE_AGENT_API_KEY` | none |
| `custom` | from `SKAPIE_AGENT_BASE_URL` (env/dart-define only; not in the settings panel) | `SKAPIE_AGENT_API_KEY` | none |
| `fake` | — | — | — |

Known presets own their base URL. Settings does **not** ask for a base URL or a typed model id.

OpenCode Go’s `x-opencode-session` is generated once per `AgentSession` and reused on vanilla requests for that controller. **Apply** creates a new session id. Connect uses `GET /models`, then joins that list with [`lib/providers/opencode_go/opencode_go_catalog.json`](../lib/providers/opencode_go/opencode_go_catalog.json). Send routes by catalog `surface`. Unknown live ids are shown disabled and are never posted as completions.

### Config resolution

1. **Last Apply** from settings (`AgentPrefs` + in-memory key) wins.
2. Else dart-define / env (`resolveAgentRuntime`).
3. Else Fake.

Missing key, missing model, unknown provider, or `custom` without a base URL → Fake.

### Prefs vs API key

Prefs persist at **`<Application Support>/skapie/agent_prefs.json`**: schema version 2.

| Field | Written |
|---|---|
| `provider` | always |
| `model` | when non-empty |
| `thinkingLevel` | when set and not `off` |
| `apiKey` | when non-empty. Local Application Support only. |
| `sendKitTools` | only when `false` (legacy; vanilla first Enter never sends tools) |

**The API key may live in Application Support prefs so quit/relaunch and reopening settings keep Connect state. It is never written into `scene.json` and never committed. No Keychain in this phase.**

### Vanilla payload (first Enter)

`buildVanillaClient` picks a surface from the OpenCode Go chart (other presets still use completions). Details and how to add a row: [providers](providers.md).

Headers (all surfaces):

- `Authorization: Bearer <apiKey>` (never logged, never shown on the kit)
- `Content-Type: application/json`
- Preset extras from the table above
- messages also sends `x-api-key` with the same key

No `tools`. No system message. No `reasoning`. Stub kits on the board do not change this body.

Timeouts (60s) and non-2xx throw `AgentHttpException`. `lastDiagnostic` records preset, model, surface, URL, status, truncated body, `tools=off`, `reasoning=off`. Never the API key.

### Future wired harness payload (not first Enter)

`OpenAiCompatibleAgentModel` + `AgentSession.sendUser` still map the full session: system / user / assistant / tool messages, optional function `tools` with object JSON Schema, and OpenRouter-only `reasoning.effort`. Selection Enter does not take this path.

## Command palette

Space or F3 (canvas focused, not typing in a field) opens a transient paint panel in the upper third. Esc, click-away, or running an action closes it. Filter is case-insensitive substring (spaces/hyphens ignored). **Hover** and **Up/Down** (optional **Ctrl-N/P**) share one highlight index; **Enter** runs the highlight (same as click). Focus stays in Search; arrows do not move the caret between actions. Highlight clamps at the list ends and scrolls into view. The palette does **not** send chat.

Actions: Add LLM, Add System Prompt, Add Tools, Add Box/Text/Button/Debug rect/Note card, Settings.

Empty world shows a muted `Space to add` hint. First LLM comes from **Add LLM**, then select and type.

Cmd+, still opens Agent settings (also listed in the palette). Add remains in that sheet.

## Selection typing (compound LLM)

`harness.llm` is a **specialized** compound kit: title-bar chrome (diamond + LLM + model if set) on the frame, stacked **Input** and **Output** regions, per-kit `provider` / `model` / `surface` props. Frame and body move together; the body is not a free-floating note. Labels live in visible `content`; props stay `prompt` vs `reply`/`error`. Not separate scene kits.

When selection is an LLM kit frame or body, the inspector hosts the model picker, Input, read-only Output, Run, and attached Tools. Input binds to `prompt` via `KitApi.updateProps`. Enter or Run calls `sendUser` with that body’s id and the kit’s model/surface. Empty prompt shows **Needs input** and is a no-op. There is no bottom LLM bar. Other selection: Space is palette only; there is no global agent capture.

`lib/agent/` is transitional runtime (controller, session, tool loop). Those capabilities become board kits later. Do not treat the agent folder as a chatbot.

### Harness kits

| Kit id | Role this phase |
|---|---|
| `harness.llm` | Specialized compound: title-bar chrome, per-kit model, Needs input, Input region, Output region. Frame and body stay glued. Props: `prompt`, `reply`, `error`, `model`, `provider`, `surface`, plus visible `content`. Palette instantiates. Inspector Enter/Run publishes onto **that** body. |
| `harness.system-prompt` | Stub. Editable text. Reserved `attachedTo` prop (empty). Add from the palette. Does not inject. |
| `harness.tools` | Stub. Lists current kit tool names as text. Reserved `attachedTo`. Does not attach `tools` to the vanilla request. |

Packages: [`kits/harness.llm/kit.json`](../kits/harness.llm/kit.json), [`kits/harness.system-prompt/kit.json`](../kits/harness.system-prompt/kit.json), [`kits/harness.tools/kit.json`](../kits/harness.tools/kit.json). World tool grants: [`docs/tools.md`](tools.md). `createAppKitApi` registers the same kit recipes; disk replaces memory.

Later turns update the selected LLM kit. No transcript strip. No drop animation.

### Settings (Connect → pick)

Provider dropdown: `fake`, `opencode-go`, `openrouter`, `openai`. Paste API key → **Connect** → `GET {preset baseUrl}/models`. Thinking row only when the catalog lists efforts (OpenRouter). Thinking does **not** ride on vanilla first Enter.

- **Apply** — requires a selected catalog model and a key. Saves prefs, rebuilds `AgentSession` and the vanilla client.
- **Use Fake** — persists provider `fake` without requiring a key.

Unknown live ids stay in the list as disabled (`not in Skapie catalog yet`). They cannot be Applied.

## Kit tools (9.1, later wire)

Implemented from the [kit API tool table](kit_api.md#agent-tools-phase-91). The tools stub kit **shows** those names. Vanilla first Enter does not send them.

## Fake vs HTTP

- **Fake:** `Echo: <text>` locally. No network. Still publishes `harness.llm`. Session messages stay at the system prompt.
- **Vanilla HTTP:** one user message. LLM kit shows reply or redacted error.
- **Session HTTP:** still available via `session.sendUser` for tests and a later board wire.

## Errors

If vanilla `complete` throws:

1. `AgentController.sendUser` still publishes the LLM kit with the error.
2. Then it rethrows.
3. The selection prompt field swallows the throw; the kit is the visible surface.

## Run with a real model

Never commit API keys. Paste in **Agent settings**; stored in Application Support prefs, not the scene.

```bash
flutter run -d macos \
  --dart-define=SKAPIE_AGENT_PROVIDER=opencode-go \
  --dart-define=SKAPIE_AGENT_API_KEY="$OPENCODE_API_KEY" \
  --dart-define=SKAPIE_AGENT_MODEL=kimi-k2.6
```

No key → Fake Echo on `harness.llm`.

macOS sandbox needs `com.apple.security.network.client` for outbound HTTP.

## Later arcs

- Visible plugs (wires) so system prompt / tools / input kits compose onto the LLM kit
- Detach Input/Output into separate kits
- Cable/graph visualization
- Wire system-prompt + tools kits into the HTTP payload
- Streaming tokens
- Pi / MCP / OAuth / Keychain
- Sandbox kits / workers
- Living sub-agent kits
- Direct `SceneStore.apply` from chat or settings
