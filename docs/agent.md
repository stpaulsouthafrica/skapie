# Agent harness

Phase 9 is the session/turn loop. **9.1** added kit **tools**. **9.2** added an OpenAI-compatible HTTP model, named presets, and overlay chat. **Phase 10** adds agent settings (rebuild the live session), a Fake vs live status chip, and a thin empty state. The tool loop is unchanged.

The message log is session state. The **scene document** remains the source of truth for the canvas. Tools never call `SceneStore.apply` themselves — they go `AgentSession` → dispatcher → `KitApi` → `apply`. Settings UI and chat must not edit the scene. **Kit** / **kit recipe** / **kit package**: [glossary](glossary.md).

## What this is / isn’t

| In 10 | Later (not this core) |
|---|---|
| Settings: provider / model / key / optional base URL | Streaming tokens |
| Apply rebuilds `AgentSession` on the same `KitApi` | Pi port, MCP, OAuth, Anthropic Messages path |
| Prefs: provider + model + base URL (no key on disk) | Chat history persistence, markdown chrome |
| Overlay chat + Fake/live chip + empty-state prompts | Sandbox kits, visible sub-agent kits, workers |

Dream goal (visible sub-agent kits on the canvas) is **not** this harness.

## Mental model

1. A **session** holds messages (starts with one system message) and a stable `id`.
2. A **turn** = user message → model → optional tool calls → tool result messages → model again → assistant text.
3. Chat listens to `events` and the message list. It only calls `session.sendUser`.
4. `AgentController` owns the current session. **Apply** in settings replaces it (new `id`, system prompt kept, prior user/assistant/tool turns cleared so a new provider does not see old tool-call history).
5. The **model** is an interface. Tests use Fake or Scripted. Real runs use `OpenAiCompatibleAgentModel` when config resolves.

```
sendUser("add a box")
  → append user
  → AgentTurnStarted
  → AgentMessageAppended (user)
  → loop (max 8):
       model.complete(messages, tools)
       if no toolCalls:
         append assistant text → finished → return
       else:
         append assistant (stores toolCalls)
         for each call: dispatch → KitApi → append role=tool (toolCallId + JSON)
  → if still calling tools after 8: append "Tool loop limit reached", finished
```

Default system prompt (`defaultAgentSystemPrompt`): use kit tools to change the scene; prefer `instantiate_kit` / `list_kits` / `add_object`; say **kit** / **kit recipe** / **kit package**, never bare “recipe.” Override with `AgentSession(systemPrompt: …)`.

## Public surface

| Type | Role |
|---|---|
| `AgentRole` | `system`, `user`, `assistant`, `tool` |
| `AgentMessage` | `role` + `content`. Assistant tool-call steps set `toolCalls`. Tool results set `toolCallId`. |
| `AgentModel` | `complete(messages:, tools:)` → `AgentModelReply` |
| `FakeAgentModel` | `Echo: <last user text>` — ignores tools |
| `ScriptedAgentModel` | Dequeues `AgentModelReply` values (for tests) |
| `OpenAiCompatibleAgentModel` | One HTTP client; POST `{baseUrl}/chat/completions` |
| `AgentSession` | Requires `kitApi`. `id`, `messages`, `events`, `sendUser`, `maxToolIterations` (default 8) |
| `AgentController` | Replaceable session + runtime; `applySettings` / `useFake` |
| `AgentPrefs` / `AgentPrefsStore` | Non-secret prefs file (no API key) |
| `resolveAgentRuntime` / `mergeAgentRuntime` | Env/defines vs last Apply |
| `createKitAgentTools` | The kit tool list bound to one `KitApi` |

## Provider presets

One HTTP client. A const table fills base URL, key env, and optional headers.

| Preset id | Default base URL | Key env (also dart-define twin) | Extra headers |
|---|---|---|---|
| `opencode-go` | `https://opencode.ai/zen/go/v1` | `OPENCODE_API_KEY` / `SKAPIE_AGENT_API_KEY` | `x-opencode-session: <AgentSession.id>` (stable for the session), `User-Agent: skapie/0.1` |
| `openrouter` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` / `SKAPIE_AGENT_API_KEY` | `HTTP-Referer: https://skapie.local`, `X-Title: Skapie` |
| `openai` | `https://api.openai.com/v1` | `OPENAI_API_KEY` / `SKAPIE_AGENT_API_KEY` | none |
| `custom` | from `SKAPIE_AGENT_BASE_URL` or settings Base URL (required) | `SKAPIE_AGENT_API_KEY` | none |
| `fake` | — | — | — |

OpenCode Go’s `x-opencode-session` is generated once per `AgentSession` and sent on every request. **Apply** creates a new session id. Stay on `/v1/chat/completions`.

### Config resolution

1. **Last Apply** from settings (`AgentPrefs` + in-memory key) wins.
2. Else dart-define / env (`resolveAgentRuntime` as in 9.2).
3. Else Fake.

`String.fromEnvironment` dart-defines plus `Platform.environment`, same pattern as the scene / kits roots.

Within a resolve: `SKAPIE_AGENT_API_KEY` wins over the preset’s native env. Explicit base URL wins over the preset default. `SKAPIE_AGENT_MODEL` is required when not Fake. Missing key, missing model, unknown provider, or `custom` without a base URL → `FakeAgentModel`.

Suggested model examples only (not hardcoded as runtime defaults): OpenCode Go `kimi-k2.6`; OpenRouter `anthropic/claude-sonnet-4`; OpenAI `gpt-4o-mini`.

### Prefs vs API key

Non-secret prefs persist at **`<Application Support>/skapie/agent_prefs.json`** (same family as `scene.json`): `provider`, `model`, optional `baseUrl`. **The API key is never written to that file, never written into `scene.json`, and never committed.** It stays in process memory until quit. Next launch: prefs restore provider/model/base URL; the key field is blank unless env/dart-define supplies it. Without a key, Fake again.

Quit with OpenCode Go selected but no env key → Fake chip until you paste a key and Apply, or export the native key env.

### Request mapping

Session messages map to OpenAI `messages` with roles `system` / `user` / `assistant` / `tool`. Assistant steps that called tools include `tool_calls`; tool results include `tool_call_id`. Kit `AgentTool`s become OpenAI `tools` function entries. The model returns the same `AgentModelReply` shape Fake/Scripted already use — there is no second tool loop.

Timeouts (60s) and non-2xx responses throw `AgentHttpException`. Chat shows the error; the user message stays.

## Chat panel

Overlay on the **left** of the canvas stack (inspector stays on the right). Opening chat or settings does **not** shrink the viewport. Toggle with the header Chat button.

Header chip: **Fake** or `{preset} · {model}`. Gear opens **Agent settings** in the same overlay (Cancel / close without Apply leaves the running session unchanged).

Empty state (no user messages yet): one line that you are Fake or live, plus suggested prompts — *Add a box near the center*, *Instantiate the demo note kit*, *List kits*. Tapping a suggestion fills the input.

The panel lists user / assistant / tool lines (plain text), a field, and Send. Send is disabled while a turn is in flight. It calls `session.sendUser` only — never `KitApi`. Failures and resolve warnings show as an error line.

One shared `AgentController` is created at bootstrap with the live `KitApi`. Tests may pass `SkapieApp(agentSession: …)` (wrapped as Fake) or `agentController:`.

### Settings (Apply)

Fields: provider dropdown (`opencode-go`, `openrouter`, `openai`, `custom`, `fake`), model, obscured API key (paste allowed), base URL (required for `custom`; optional override otherwise).

- **Apply** — save prefs (no key), rebuild `AgentSession` from `mergeAgentRuntime`. Clears prior turns; keeps the default system prompt.
- **Use Fake** — one-click `FakeAgentModel` (also persisted as provider `fake`).
- **Cancel** — close the form; session unchanged.

## Kit tools (9.1)

Implemented from the [kit API tool table](kit_api.md#agent-tools-phase-91). Snake_case tool names; Dart methods stay `addObject`, `instantiate`, etc.

Success shapes: `list_kits` → `{kits:[{id,displayName}]}`; `get_kit` → `{kit:…}` or error; `add_object` → `{id}`; `instantiate_kit` → `{ids}`; mutations → `{ok:true}` (`save_kit` / `register_kit` also `id`; `reload_packages` also `count`).

Failures (unknown tool, bad JSON, unknown `typeId` / kit, thrown `ArgumentError`): `{ "ok": false, "error": "…" }` as the **tool message content**. The session does **not** throw. Scene unchanged when `KitApi` rejects.

## Fake vs Scripted vs HTTP

- **Fake:** always plain text. Used when no key/model, **Use Fake**, and widget tests.
- **Scripted:** first replies may include `toolCalls`; a later reply with empty `toolCalls` is the final assistant text.
- **HTTP:** OpenAI-compatible chat completions. Same tool loop underneath.

## Errors

If `complete` throws:

1. The user message **stays**.
2. `AgentTurnFailed` is emitted (no `AgentTurnFinished`).
3. `sendUser` **rethrows** (chat shows it).
4. Tool dispatch errors do **not** use this path.

**Max iterations:** after `maxToolIterations` model replies that still have tool calls, append assistant `Tool loop limit reached`, emit finished, do not throw.

## Run with a real model

Never commit API keys. Startup env/dart-define still works. You can also paste a key in **Agent settings** (memory only).

```bash
# OpenCode Go
flutter run -d macos \
  --dart-define=SKAPIE_AGENT_PROVIDER=opencode-go \
  --dart-define=SKAPIE_AGENT_API_KEY="$OPENCODE_API_KEY" \
  --dart-define=SKAPIE_AGENT_MODEL=kimi-k2.6

# OpenRouter
flutter run -d macos \
  --dart-define=SKAPIE_AGENT_PROVIDER=openrouter \
  --dart-define=SKAPIE_AGENT_API_KEY="$OPENROUTER_API_KEY" \
  --dart-define=SKAPIE_AGENT_MODEL=anthropic/claude-sonnet-4
```

Or export `OPENCODE_API_KEY` / `OPENROUTER_API_KEY` in the shell and only pass provider + model defines. Or run with no key, open Chat → gear, paste, Apply.

No key → Fake; Chat Echo works; the canvas is unchanged by chat text alone.

macOS sandbox needs `com.apple.security.network.client` (Debug and Release) for outbound HTTP.

## Later arcs (not Phase 10)

- Streaming tokens
- Pi port / MCP / sub-agents / OAuth
- Anthropic-native OpenCode Go endpoints
- Sandbox kits / `capabilities` / workers
- Visible sub-agent kits on the canvas (dream goal)
- Personal coding-agent kit (allowlisted FS/shell)
- Multi-session history persistence
- Fancy markdown chat chrome
- Direct `SceneStore.apply` from chat or settings
