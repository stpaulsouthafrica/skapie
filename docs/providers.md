# Providers catalog

Skapie ships a curated **seating chart** so live `/models` ids can be joined to an API surface. Live OpenCode Go `GET …/v1/models` returns ids only. The chart says which HTTP surface to call.

Remote / WordPress overlays are out of scope. Edit the JSON in the repo.

## Where the chart lives

| Path | Role |
|---|---|
| [`lib/providers/opencode_go/opencode_go_catalog.json`](../lib/providers/opencode_go/opencode_go_catalog.json) | Human-edited source of truth |
| [`lib/providers/opencode_go/opencode_go_catalog.dart`](../lib/providers/opencode_go/opencode_go_catalog.dart) | Parser + embedded copy (keep identical to the JSON) |
| [`lib/providers/model_surface.dart`](../lib/providers/model_surface.dart) | `completions` / `responses` / `messages` |
| [`lib/providers/merge_live_models.dart`](../lib/providers/merge_live_models.dart) | Connect join: live ∩ chart |
| [`lib/providers/vanilla_responses.dart`](../lib/providers/vanilla_responses.dart) | Vanilla POST `/responses` |
| [`lib/providers/vanilla_messages.dart`](../lib/providers/vanilla_messages.dart) | Vanilla POST `/messages` |
| [`lib/agent/vanilla_completion.dart`](../lib/agent/vanilla_completion.dart) | Vanilla POST `/chat/completions` |

Base URL stays `https://opencode.ai/zen/go/v1` (same as the `opencode-go` preset).

## How Connect merges

For `opencode-go` only:

1. Fetch live `GET {base}/models` (existing `fetchAgentModels`).
2. Join by id with the curated chart.
3. Picker shows live ids that are in the chart with `show: true`, plus unknown live ids as **disabled** with subtitle `not in Skapie catalog yet`.
4. Chart-only ids missing from live `/models` are omitted (offline / unavailable).
5. Selected model id is persisted as today. On send, surface is resolved from the chart, never guessed.

Unknown live ids are **not** posted as completions.

## Surfaces (vanilla first Enter)

First Enter is still user text only: no tools, no Skapie system prompt, no reasoning blob.

| Surface | POST | Body |
|---|---|---|
| `completions` | `{base}/chat/completions` | `{ model, messages: [{ role: user, content }] }` |
| `responses` | `{base}/responses` | `{ model, input: "<text>" }` |
| `messages` | `{base}/messages` | `{ model, max_tokens: 1024, messages: [{ role: user, content }] }` |

Headers: `Authorization: Bearer`, OpenCode `x-opencode-session`, `User-Agent: skapie/0.1`. The messages client also sends `x-api-key` (same key). No `anthropic-version` unless a future probe proves Go requires it.

Routing is one `switch (surface)` in `buildVanillaClient`.

## Add a model row

1. Confirm the **live** id from `GET https://opencode.ai/zen/go/v1/models`.
2. Add a row to `opencode_go_catalog.json`:

```json
{ "id": "the-live-id", "surface": "completions", "displayName": "Nice name" }
```

`surface` is `completions`, `responses`, or `messages` (Pi aliases `openai-completions` / `openai-responses` / `anthropic-messages` also parse). `show` defaults true. Set `"show": false` to hide a live id.

3. Copy the same row into the embedded `opencodeGoCatalogJson` string in `opencode_go_catalog.dart`.
4. Run tests. The catalog-file equality test fails if JSON and embed drift.
