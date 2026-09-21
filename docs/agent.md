# Agent harness

Phase 9 is the session/turn loop. **Phase 9.1** added kit **tools** that call `KitApi`. **Phase 9.2** adds an OpenAI-compatible HTTP model, named provider presets, and a thin overlay chat panel. The tool loop is unchanged.

The message log is session state. The **scene document** remains the source of truth for the canvas. Tools never call `SceneStore.apply` themselves — they go `AgentSession` → dispatcher → `KitApi` → `apply`. Chat UI must not edit the scene. **Kit** / **kit recipe** / **kit package**: [glossary](glossary.md).

## What this is / isn’t

| In 9.2 | Not yet (Phase 10 / later) |
|---|---|
| `OpenAiCompatibleAgentModel` (`POST …/chat/completions`) | Streaming tokens |
| Presets: `opencode-go`, `openrouter`, `openai`, `custom` | Pi port, MCP, OAuth, Anthropic Messages path |
| Overlay chat → `sendUser` | Chat history persistence, markdown chrome |
| Fake fallback when key/model missing | Sandbox kits, sub-agents, product polish |

Dream goal (visible sub-agent kits on the canvas) is **not** this harness.

## Mental model

1. A **session** holds messages (starts with one system message) and a stable `id`.
2. A **turn** = user message → model → optional tool calls → tool result messages → model again → assistant text.
3. Chat listens to `events` and the message list. It only calls `session.sendUser`.
4. The **model** is an interface. Tests use Fake (text echo) or Scripted (queued replies). Real runs use `OpenAiCompatibleAgentModel` when config resolves.

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
| `AgentTool` / `AgentToolDispatcher` | Name + `run`; `dispatch(name, argumentsJson)` |
| `createKitAgentTools` | The kit tool list bound to one `KitApi` |
| `resolveAgentRuntime` | Preset + key + base URL + model (or Fake) |

## Provider presets

One HTTP client. A const table fills base URL, key env, and optional headers.

| Preset id | Default base URL | Key env (also dart-define twin) | Extra headers |
|---|---|---|---|
| `opencode-go` | `https://opencode.ai/zen/go/v1` | `OPENCODE_API_KEY` / `SKAPIE_AGENT_API_KEY` | `x-opencode-session: <AgentSession.id>` (stable for the session), `User-Agent: skapie/0.1` |
| `openrouter` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` / `SKAPIE_AGENT_API_KEY` | `HTTP-Referer: https://skapie.local`, `X-Title: Skapie` |
| `openai` | `https://api.openai.com/v1` | `OPENAI_API_KEY` / `SKAPIE_AGENT_API_KEY` | none |
| `custom` | from `SKAPIE_AGENT_BASE_URL` (required) | `SKAPIE_AGENT_API_KEY` | none |

OpenCode Go’s `x-opencode-session` is generated once per `AgentSession` and sent on every request. Stay on `/v1/chat/completions`. Do not port Pi’s catalog, OAuth, or Anthropic Messages.

### Config resolution

`String.fromEnvironment` dart-defines plus `Platform.environment`, same pattern as the scene / kits roots. Keys are never written to disk or into the scene file.

1. Provider: `SKAPIE_AGENT_PROVIDER` dart-define or env. If unset: `OPENCODE_API_KEY` → `opencode-go`; else `OPENROUTER_API_KEY` → `openrouter`; else `OPENAI_API_KEY` or `SKAPIE_AGENT_API_KEY` → `openai` (or `custom` if a base URL is set); else Fake.
2. Base URL: explicit `SKAPIE_AGENT_BASE_URL` wins; else the preset default (`custom` requires an explicit base URL).
3. API key: `SKAPIE_AGENT_API_KEY` wins; else the preset’s native env.
4. Model: `SKAPIE_AGENT_MODEL` is required when not Fake. Suggested examples only (not hardcoded as runtime defaults): OpenCode Go `kimi-k2.6`; OpenRouter `anthropic/claude-sonnet-4`; OpenAI `gpt-4o-mini`.
5. Missing key, missing model, unknown provider, or `custom` without a base URL → `FakeAgentModel`.

### Request mapping

Session messages map to OpenAI `messages` with roles `system` / `user` / `assistant` / `tool`. Assistant steps that called tools include `tool_calls`; tool results include `tool_call_id`. Kit `AgentTool`s become OpenAI `tools` function entries. The model returns the same `AgentModelReply` shape Fake/Scripted already use — there is no second tool loop.

Timeouts (60s) and non-2xx responses throw `AgentHttpException`. Chat shows the error; the user message stays.

## Chat panel

Overlay on the **left** of the canvas stack (inspector stays on the right). Opening chat does **not** shrink the viewport. Toggle with the header Chat button.

The panel lists user / assistant / tool lines (plain text), a field, and Send. Send is disabled while a turn is in flight. It calls `session.sendUser` only — never `KitApi`. Failures show as an error line (`AgentTurnFailed` / thrown error).

One shared `AgentSession` is created at bootstrap with the live `KitApi` and the resolved model. Tests may pass `SkapieApp(agentSession: …)`. If omitted, the app uses `FakeAgentModel` on the same `KitApi`.

## Kit tools (9.1)

Implemented from the [kit API tool table](kit_api.md#agent-tools-phase-91). Snake_case tool names; Dart methods stay `addObject`, `instantiate`, etc.

Success shapes: `list_kits` → `{kits:[{id,displayName}]}`; `get_kit` → `{kit:…}` or error; `add_object` → `{id}`; `instantiate_kit` → `{ids}`; mutations → `{ok:true}` (`save_kit` / `register_kit` also `id`; `reload_packages` also `count`).

Failures (unknown tool, bad JSON, unknown `typeId` / kit, thrown `ArgumentError`): `{ "ok": false, "error": "…" }` as the **tool message content**. The session does **not** throw. Scene unchanged when `KitApi` rejects.

## Fake vs Scripted vs HTTP

- **Fake:** always plain text. Used when no key/model, and in widget tests.
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

Never commit API keys. Prefer shell env plus dart-defines for provider and model:

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

Or export `OPENCODE_API_KEY` / `OPENROUTER_API_KEY` in the shell and only pass provider + model defines.

No key → Fake; Chat Echo works; the canvas is unchanged by chat text alone.

macOS sandbox needs `com.apple.security.network.client` (Debug and Release) for outbound HTTP.

## Roadmap

- **Phase 10** — product polish. Blocked until this gate is green.
- Later — Pi port, sub-agents, MCP, sandbox kits, workers, streaming.

## Non-goals (this slice)

- Streaming tokens
- Pi port / MCP / sub-agents / OAuth
- Anthropic-native OpenCode Go endpoints
- Executing `capabilities` / workers
- Direct `SceneStore.apply` from chat or agent code
- Multi-session history persistence
- Fancy markdown chat chrome
