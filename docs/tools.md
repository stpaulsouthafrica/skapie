# Tool kits

A tool has a **host-owned runner** and a **visible grant kit** on the board. A `kit.json` file supplies the kit recipe and its `toolName`; it does not execute code. An LLM receives only tools whose grant kits are connected to its Tools port. With no connected grants, the LLM uses the vanilla completion path.

World runners in [`lib/tools/world/`](../lib/tools/world/) call `KitApi` to inspect or change the Skapie scene. Repository runners in [`lib/tools/repository/`](../lib/tools/repository/) read a user-chosen folder. These are different capabilities, even though both appear as individual `tools.*` kits.

## Build a repository reader on the board

1. Add an LLM, a Repository, and whichever repository tools are needed.
2. Select Repository → **Choose folder**. On macOS, the app saves a read-only security-scoped bookmark. The board saves the selected path, but a path alone does not grant access.
3. Cable Repository Output to the Repository input of each chosen tool. Each tool accepts one Repository source.
4. Cable each tool Output to LLM Tools. A tool with no LLM cable is not offered to the model. A repository tool with no Repository cable returns an error if called.
5. Connect Text to LLM Input and optionally Conversation to LLM Conversation. Run from the LLM inspector.

The active tool's LLM and Repository cables pulse. The LLM inspector has a collapsible **Run activity** section with calls, arguments, results, and states from the latest run. This activity is in memory for now.

Available repository grants:

| Kit id | Runner action |
|---|---|
| `tools.repo_list_files` | List up to 500 paths, excluding generated folders and likely secret filenames. |
| `tools.repo_search_text` | Search text and return bounded path, line, and excerpt matches. |
| `tools.repo_read_file` | Read up to 200 lines of one relative file. |
| `tools.repo_git_status` | Read branch and working tree status. |
| `tools.repo_git_diff` | Read a bounded working tree or staged diff. |

File paths are repository-relative. The host rejects traversal and symlink escape; generated folders and likely secret filenames are skipped. These guards reduce accidental disclosure but do not classify every sensitive file. The folder picker defines the repository scope.

## World tool grants

World tools remain individual kits under `kits/tools.<name>/` and runners under `lib/tools/world/`:

| Tool | Action |
|---|---|
| `list_kits`, `get_kit` | Inspect registered kit recipes. |
| `instantiate_kit`, `add_object`, `remove_object` | Change scene objects through `KitApi`. |
| `update_frame`, `update_props`, `set_locked` | Edit scene objects through `KitApi`. |
| `save_kit`, `reload_packages`, `register_kit` | Manage kit recipes and packages. |

The palette offers **Tool: ...** entries, plus **Patch Proposal**, **Review Decision**, and **Apply Patch**. You can cable a tool's Output to the LLM's Tools port or use **Attach to LLM** / the inspector's Allowed connections list. Cutting a cable removes that connection. `harness.tools` remains a stub roster, not a grant. Unknown `toolName` is shown as an error on the kit and is omitted from the request.

## Patch proposal, review, and apply

These are four separate board pieces. Wiring them never writes the repository.

| Kit id | Kind | Role |
|---|---|---|
| `tools.propose_patch` | Tool grant | The model may call `propose_patch` with one repository-relative path, the exact existing text, and the replacement. The host reads that UTF-8 file, fingerprints it, and stores a display diff on the cabled Patch Proposal. A model-supplied base hash is ignored. The call does not approve or apply. |
| `coding.patch_proposal` | Artifact | Structured proposal data. Not a tool and not offered to the model. |
| `coding.review_decision` | User kit | Holds the engineer's decision. A model's Propose call cannot create an Accept. |
| `coding.apply_patch` | Effect | Writes only after a valid review decision. Connecting a cable does not apply. Apply stays inert until that decision exists. |

Cable Propose Result → Proposal In, Proposal Out → Review In, and Review Out → Apply In. The existing Repository read grant is not write authority.

The runner list is registered in app code. A user can compose and save kit arrangements today; declaring a new `toolName` in `kit.json` does not install a runner. Typed ports and a user-facing capability contract are planned in the [Phase 11 roadmap](phase_11_roadmap.md).
