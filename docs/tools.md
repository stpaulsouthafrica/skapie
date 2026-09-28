# Tool kits

A tool has a **host-owned runner** and a **visible grant kit** on the board. A `kit.json` file supplies the kit recipe and its `toolName`; it does not execute code. An LLM receives only tools whose grant kits are connected to its Tools port. With no connected grants, the LLM uses the vanilla completion path.

The default shelf has four tools, all on the [starter board](phase_12.md): **Read**, **Write**, **Edit**, and **Shell**. Everything else is a user package; the old checks, Propose/Review/Apply, Run Control, and kit-author world tools are demoted to [`examples/kits/`](../examples/README.md) and explained in the [rebuild notes](phase_12_rebuild_notes.md).

## Build a coding agent on the board

1. Add an **LLM**, a **Conversation**, a **Repository**, and the tools you want.
2. Draft the request in a **Text** kit and cable its Out to the LLM **Input**. Cable the model reply to an output **Text** or to **Conversation**.
3. Select **Repository** and choose a **read folder** and a **write folder**. Each is a separate macOS bookmark; a read bookmark never satisfies a write.
4. Cable Repository **Out** to Read's **Repository** input. Cable Repository **Write** to the **Write** input of Write, Edit, and Shell.
5. Cable each tool's **LLM** output to the LLM **Tools** port. A tool with no Tools cable is not offered to the model.
6. Run from the LLM inspector.

The active tool's LLM and Repository cables pulse. The LLM inspector has a collapsible **Run activity** section with calls, arguments, results, and states from the latest run.

## The four tools

| Tool | Runner | Grant | Notes |
|---|---|---|---|
| `read` | `lib/tools/coding/read_tool.dart` | Repository read | `action` is `list`, `search`, or `read`. |
| `write` | `lib/tools/coding/write_tool.dart` | Repository write | Create or replace one UTF-8 file. Optional `expectedFingerprint` refuses a stale overwrite. |
| `edit` | `lib/tools/coding/edit_tool.dart` | Repository write | Replace one exact substring that appears once. |
| `shell` | `lib/tools/coding/shell_tool.dart` | Repository write | `/bin/sh -c` with the granted folder as cwd. Commands that point outside the folder are refused. |

Path safety lives in `lib/tools/coding/scoped_path.dart`: generated and secret names are skipped, `..` and absolute paths are refused, and symlink escapes are blocked. A write never leaves the granted folder.

The model cannot choose an absolute root and cannot satisfy a grant with board text. A missing cable, a missing folder, or expired access shows up as a filtered tool with a reason in the LLM inspector.

## Register a new runner

A user composes and saves kit arrangements today. Declaring a new `toolName` in `kit.json` does not install a runner. The runner table is host code:

- The four coding tools resolve in [`lib/tools/coding/coding_tools.dart`](../lib/tools/coding/coding_tools.dart).
- New runners need an explicit host spike; Phase 12 forbids new first-party feature kits.

A package declares its own ports from the host vocabulary and can name an existing
runner. A wider capability contract (MCP-class packages) stays a package, not a
shipped host feature. See the [Phase 12 inventory](phase_12_inventory.md) for
every host special-case.
