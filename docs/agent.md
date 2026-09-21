# Agent harness

The **world is the harness.** The bottom chat bar is an on-ramp, not a hidden full agent stack.

**Phase 10.3.1:** first Enter is vanilla user text only. OpenCode Go models are joined to a curated seating chart and routed to completions, responses, or messages. The reply lands on an **LLM kit**. **System prompt** and **Tools** are separate stub kits you can place on the board. Wiring those kits into the HTTP payload is later. The tool-loop `AgentSession` still exists for that later wire; chat Enter does not use it.

The **scene document** remains the source of truth. Mutations go `KitApi` → `SceneStore.apply`. Settings and the chat widget do not call `KitApi`. `AgentController.sendUser` publishes the LLM kit through `KitApi`. **Kit** / **kit recipe** / **kit package**: [glossary](glossary.md). Chart file and how to add a row: [providers](providers.md).

## What this is / isn’t

| In 10.3.1 | Later |
|---|---|
| Vanilla first Enter on the model’s surface (user text only) | Inject system prompt + tools from board kits |
| OpenCode Go catalog in `lib/providers/` | Remote / WordPress catalog overlay |
| LLM kit, system-prompt stub kit, tools stub kit | Cable/graph connection renderer |
| Prefs: provider + model + local key (never scene.json) | Streaming, MCP, OAuth, Keychain |
| Minimal chat field | Fat chat transcript chrome |

Living sub-agent kits (status, tokens, workers) remain a dream goal. These harness kits are static box + text first principles.

## Mental model

1. Settings supply the **pipe**: provider, base URL, API key, model.
2. Chat Enter sends **vanilla** user text when live (or Fake Echo offline). Surface comes from the OpenCode Go chart.
3. Success or failure materializes / updates `harness.llm` on the world.
4. `harness.system-prompt` and `harness.tools` can sit on the board. They do **not** change the vanilla payload.
5. `AgentSession` (system prompt + kit tools loop) is kept for a later wire. First Enter does not call `session.sendUser`.

```
controller.sendUser("hello")
  → if Fake: reply = "Echo: hello"
  → else buildVanillaClient(catalog.surface).complete(userText)
       completions → POST {baseUrl}/chat/completions
                     { model, messages: [{ role: user, content }] }
       responses   → POST {baseUrl}/responses
                     { model, input }
       messages    → POST {baseUrl}/messages
                     { model, max_tokens: 1024, messages: [{ role: user, content }] }
  → publishLlmKit via KitApi (success or failure)
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
| `VanillaCompletionClient` | Plain POST `/chat/completions`. One user message. No tools. No system. No reasoning. |
| `VanillaResponsesClient` | Plain POST `/responses`. `{ model, input }`. |
| `VanillaMessagesClient` | Plain POST `/messages`. `{ model, max_tokens, messages: [user] }`. |
| `UnverifiedVanillaClient` | Live id not in the chart. Throws; does not POST completions. |
| `AgentHttpException` | Non-2xx / timeout. Carries `statusCode` + `body` when HTTP. |
| `AgentHttpDiagnostic` | Redacted request summary (provider, model, surface, URL, status, body). Never the API key. |
| `publishLlmKit` | Instantiates or updates `harness.llm` through `KitApi` |
| `AgentController.sendUser` | Vanilla on-ramp, then LLM kit |
| `AgentSession` | Later tool-loop harness. Not the default first Enter. |
| `OpenAiCompatibleAgentModel` | Session HTTP model (tools + optional OpenRouter reasoning) |
| `FakeAgentModel` | `Echo: <last user text>` for session tests |
| `AgentPrefs` / `AgentPrefsStore` | Application Support prefs (optional local `apiKey`) |
| `createKitAgentTools` | Kit tool list for the later session loop |

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

`OpenAiCompatibleAgentModel` + `AgentSession.sendUser` still map the full session: system / user / assistant / tool messages, optional function `tools` with object JSON Schema, and OpenRouter-only `reasoning.effort`. Chat Enter does not take this path in 10.3.1.

## Chat panel

Overlay at the **bottom center**. About one third of the window width, capsule, field only. `/settings`, `/settings/`, or Cmd+, opens Agent settings. Add lives in that sheet.

The strip calls `controller.sendUser` on Return. The widget never calls `KitApi`.

### Harness kits

| Kit id | Role this phase |
|---|---|
| `harness.llm` | Latest vanilla turn. Props: `prompt`, `reply`, `error`, `model`, `provider`, plus visible `content`. Instantiated/updated by `publishLlmKit`. Origin `(24, 24)`. |
| `harness.system-prompt` | Stub. Editable text. Reserved `attachedTo` prop (empty). Add from the menu. Does not inject. |
| `harness.tools` | Stub. Lists current kit tool names as read-only-ish text. Reserved `attachedTo`. Does not attach `tools` to the vanilla request. |

Packages: [`kits/harness.llm/kit.json`](../kits/harness.llm/kit.json), [`kits/harness.system-prompt/kit.json`](../kits/harness.system-prompt/kit.json), [`kits/harness.tools/kit.json`](../kits/harness.tools/kit.json). `createAppKitApi` registers the same kit recipes; disk replaces memory.

Later turns update the same LLM kit. No transcript UI in the strip. No drop animation.

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
3. The chat strip swallows the throw; the kit is the visible surface.

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

## Later arcs (not Phase 10.3.1)

- Wire system-prompt + tools kits into the HTTP payload
- Cable/graph visualization
- Streaming tokens
- Pi / MCP / OAuth / Keychain
- Sandbox kits / workers
- Living sub-agent kits
- Direct `SceneStore.apply` from chat or settings
