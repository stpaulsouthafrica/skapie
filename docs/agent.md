# Agent harness

Phase 9 is the session/turn loop. **Phase 9.1** adds kit **tools** that call `KitApi`. There is still **no** chat UI and **no** HTTP provider.

The message log is session state. The **scene document** remains the source of truth for the canvas. Tools never call `SceneStore.apply` themselves — they go `AgentSession` → dispatcher → `KitApi` → `apply`. See [glossary](glossary.md), [foundation](foundation.md), [kit API](kit_api.md).

## What this is / isn’t

| In 9 / 9.1 | Not yet (**9.2**) |
|---|---|
| `AgentSession.sendUser` tool loop | Real LLM HTTP + secrets |
| `FakeAgentModel` / `ScriptedAgentModel` | Minimal chat panel / streaming |
| Kit tools bound to `KitApi` | MCP, sub-agents, Pi port |

Dream goal (visible sub-agent kits on the canvas) is **not** this harness.

## Mental model

1. A **session** holds messages (starts with one system message).
2. A **turn** = user message → model → optional tool calls → tool result messages → model again → assistant text.
3. The harness **emits events**; a chat UI will listen in 9.2.
4. The **model** is an interface. Tests use Fake (text echo) or Scripted (queued replies, including tool calls).

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

Default system prompt (`defaultAgentSystemPrompt`): *You are Skapie's canvas agent. Use kit tools to change the scene when needed.* Override with `AgentSession(systemPrompt: …)`.

## Public surface

| Type | Role |
|---|---|
| `AgentRole` | `system`, `user`, `assistant`, `tool` |
| `AgentMessage` | `role` + `content`. Assistant tool-call steps set `toolCalls`. Tool results set `toolCallId`. |
| `AgentModel` | `complete(messages:, tools:)` → `AgentModelReply` |
| `FakeAgentModel` | `Echo: <last user text>` — ignores tools |
| `ScriptedAgentModel` | Dequeues `AgentModelReply` values (for tests) |
| `AgentSession` | Requires `kitApi`. `messages`, `events`, `sendUser`, `maxToolIterations` (default 8) |
| `AgentTool` / `AgentToolDispatcher` | Name + `run`; `dispatch(name, argumentsJson)` |
| `createKitAgentTools` | The kit tool list bound to one `KitApi` |

## Kit tools (9.1)

Implemented from the [kit API tool table](kit_api.md#agent-tools-phase-91). Snake_case tool names; Dart methods stay `addObject`, `instantiate`, etc.

Success shapes: `list_kits` → `{kits:[{id,displayName}]}`; `get_kit` → `{kit:…}` or error; `add_object` → `{id}`; `instantiate_kit` → `{ids}`; mutations → `{ok:true}` (`save_kit` / `register_kit` also `id`; `reload_packages` also `count`).

Failures (unknown tool, bad JSON, unknown `typeId` / kit, thrown `ArgumentError`): `{ "ok": false, "error": "…" }` as the **tool message content**. The session does **not** throw. Scene unchanged when `KitApi` rejects.

## Fake vs Scripted

- **Fake:** always plain text. Existing Phase 9 tests.
- **Scripted:** first replies may include `toolCalls`; a later reply with empty `toolCalls` is the final assistant text.

## Errors

If `complete` throws:

1. The user message **stays**.
2. `AgentTurnFailed` is emitted (no `AgentTurnFinished`).
3. `sendUser` **rethrows**.
4. Tool dispatch errors do **not** use this path.

**Max iterations:** after `maxToolIterations` model replies that still have tool calls, append assistant `Tool loop limit reached`, emit finished, do not throw.

## Roadmap

- **9.2 Provider + chat** — real model HTTP, secrets, a thin chat panel that listens to `events`.
- Later — Pi port, sub-agents, MCP, sandbox kits, workers.

## Non-goals (this slice)

- Chat widgets / streaming tokens
- HTTP / API keys
- Executing `capabilities` / workers
- Direct `SceneStore.apply` from agent code
