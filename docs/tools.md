# World tools

A **world tool** is a named KitApi capability the model may call. It has two parts:

1. **Runner** — one Dart file under [`lib/tools/world/`](../lib/tools/world/). This is the executable.
2. **Grant** — one disk kit under `kits/tools.<name>/`. Spawning it onto the board is a visible permission, not the implementation.

The kit package does **not** contain the runner. `kit.json` is chrome plus `toolName` and `attachedTo`. An LLM with no attached tool kits stays vanilla (no `tools` array). An LLM with attached tool kits runs the existing agent tool loop with **exactly those** tools.

There is no cable editor yet. Attach is a prop/API: `attachedTo` holds the LLM body id.

## Runner vs grant

| | Runner | Grant |
|---|---|---|
| Where | `lib/tools/world/<name>.dart` | `kits/tools.<name>/kit.json` |
| What | `AgentTool` that calls `KitApi` | Scene objects you can spawn |
| Props | — | `toolName`, `attachedTo`, `skapieKit: tools.<name>` |
| Unknown `toolName` | — | Error on that kit; omitted from the tools array |

[`lib/tools/tool.dart`](../lib/tools/tool.dart) holds shared JSON-schema helpers. [`lib/tools/world/register.dart`](../lib/tools/world/register.dart) exports `createWorldTools(KitApi)`. `createKitAgentTools` remains a thin wrapper so the old session loop still compiles.

Vanilla first Enter (no attached grants) still uses the HTTP kernel in [`lib/providers/`](../lib/providers/). Coding tools (read/write/bash) are not in this set.

## World tool files and kit ids

| Runner | Kit id | Description |
|---|---|---|
| [`list_kits.dart`](../lib/tools/world/list_kits.dart) | `tools.list_kits` | List registered kits. |
| [`get_kit.dart`](../lib/tools/world/get_kit.dart) | `tools.get_kit` | Get one kit recipe by id. |
| [`instantiate_kit.dart`](../lib/tools/world/instantiate_kit.dart) | `tools.instantiate_kit` | Instantiate a kit into the scene. |
| [`add_object.dart`](../lib/tools/world/add_object.dart) | `tools.add_object` | Add one scene object. |
| [`remove_object.dart`](../lib/tools/world/remove_object.dart) | `tools.remove_object` | Remove a scene object by id. |
| [`update_frame.dart`](../lib/tools/world/update_frame.dart) | `tools.update_frame` | Patch a scene object frame. |
| [`update_props.dart`](../lib/tools/world/update_props.dart) | `tools.update_props` | Shallow-merge props. Null values remove keys. |
| [`set_locked.dart`](../lib/tools/world/set_locked.dart) | `tools.set_locked` | Set SceneObject.locked. |
| [`save_kit.dart`](../lib/tools/world/save_kit.dart) | `tools.save_kit` | Write a kit package to disk and register it. |
| [`reload_packages.dart`](../lib/tools/world/reload_packages.dart) | `tools.reload_packages` | Reload kit packages from disk. |
| [`register_kit.dart`](../lib/tools/world/register_kit.dart) | `tools.register_kit` | Register an ephemeral in-memory kit. |

Palette: **Tool: list_kits** (and the rest) instantiates the grant. **Attach to LLM** / **Detach tool** set or clear `attachedTo`. Select an LLM, then a tool kit (or the reverse); both ids are remembered.

LLM chrome shows `Tools: none` or `Tools: list_kits, add_object`. `harness.tools` remains a stub roster and is not a grant.

## Attach / Enter

1. Spawn `harness.llm` and one or more `tools.*` kits.
2. Palette **Attach to LLM** writes `attachedTo` on every object in that tool kit (KitApi `updateProps` only).
3. Enter on that LLM:
   - no attached grants, or only unknown names → vanilla completion
   - attached known names → `AgentSession` tool loop with only those `AgentTool`s
4. Detach clears `attachedTo` and refreshes the LLM Tools line.

The Skapie canvas system prompt is **not** injected on this path. Empty system text only. Wiring `harness.system-prompt` onto the payload is still later.
