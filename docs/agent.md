# Agent harness

Phase 9 is the **core loop only**: session, messages, a model port, a fake model, events. It does **not** mutate the scene. It does **not** call `KitApi`. There is **no** chat UI and **no** HTTP provider.

The message log is session state. The **scene document** remains the source of truth for the canvas. See [glossary](glossary.md) and [foundation](foundation.md).

## What this is / isn’t

| In Phase 9 | Not yet |
|---|---|
| `AgentSession.sendUser` | **9.1** tools → [Kit API sketch](kit_api.md#agent-tool-sketch-phase-91-not-implemented) |
| `AgentModel` + `FakeAgentModel` | **9.2** real LLM + minimal chat panel |
| Events for a future UI | Streaming tokens, secrets, MCP, sub-agents |

Dream goal (visible sub-agent kits on the canvas) is **not** this harness. The loop here is text in / text out.

## Mental model

1. A **session** holds messages (starts with one system message).
2. A **turn** = user message → `model.complete` → assistant message.
3. The harness **emits events**; a chat UI will listen in 9.2.
4. The **model** is an interface. Phase 9 ships `FakeAgentModel` so tests need no API keys.

```
sendUser("hi")
  → append user
  → AgentTurnStarted
  → AgentMessageAppended (user)
  → model.complete(messages)
  → append assistant
  → AgentMessageAppended (assistant)
  → AgentTurnFinished
```

Default system prompt (`defaultAgentSystemPrompt`): *You are Skapie's canvas agent. You talk about the canvas and scene. Tools come later.* Override with `AgentSession(systemPrompt: …)`.

## Public surface (`lib/agent/agent.dart`)

| Type | Role |
|---|---|
| `AgentRole` | `system`, `user`, `assistant`, `tool` |
| `AgentMessage` | `role` + `content`. Optional `toolCalls` / `toolCallId` stubs — unused until 9.1 |
| `AgentModel` | `complete(messages:)` → `AgentModelReply` |
| `FakeAgentModel` | `Echo: <last user text>` |
| `AgentSession` | `messages`, `events`, `sendUser` |
| `AgentEvent` | `AgentTurnStarted`, `AgentMessageAppended`, `AgentTurnFinished`, `AgentTurnFailed` |

`AgentToolCall` is a type placeholder for 9.1. The loop ignores `toolCalls` on the reply.

## Fake model

`FakeAgentModel.complete` finds the last user message and returns `Echo: ${text}`. Deterministic. No network.

## Errors

If `complete` throws:

1. The user message **stays** in `messages`.
2. No assistant message is appended.
3. `AgentTurnFailed(error)` is emitted (no `AgentTurnFinished`).
4. `sendUser` **rethrows**.

## Roadmap

- **9.1 Tools** — define tools, JSON args, dispatch to `KitApi`, append tool-result messages. Future list: [kit_api.md agent tool sketch](kit_api.md#agent-tool-sketch-phase-91-not-implemented). Still no scene mutation in *this* file until that slice.
- **9.2 Provider + chat** — real model HTTP, secrets, a thin chat panel that listens to `events`.
- Later — Pi port, sub-agents, MCP, sandbox kits, workers.

## Non-goals (this slice)

- `KitApi` / `SceneStore.apply` from agent code
- Chat widgets
- HTTP / API keys
- Executing `capabilities` / workers
