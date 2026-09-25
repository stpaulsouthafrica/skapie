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

The palette offers **Tool: ...** entries, plus **Patch Proposal**, **Review Decision**, **Write Scope**, and **Apply Patch**. You can cable a tool's Output to the LLM's Tools port or use **Attach to LLM** / the inspector's Allowed connections list. Cutting a cable removes that connection. `harness.tools` remains a stub roster, not a grant. Unknown `toolName` is shown as an error on the kit and is omitted from the request.

## Patch proposal, review, and apply

The proposal flow has four parts plus a separately selected Write Scope grant. Wiring them never writes the repository.

| Kit id | Kind | Role |
|---|---|---|
| `tools.propose_patch` | Tool grant | The model may call `propose_patch` with one repository-relative path, the exact existing text, and the replacement. The host reads that UTF-8 file, fingerprints it, and stores a display diff on the cabled Patch Proposal. A model-supplied base hash is ignored. The call does not approve or apply. |
| `coding.patch_proposal` | Artifact | Read-only file summary on the board; double-click or use Inspector for a focused colored diff. Not a model tool. |
| `coding.review_decision` | User kit | Accept or Reject settles for that exact proposal. Reconsider is explicit. A changed proposal invalidates the old decision. |
| `coding.write_scope` | Grant | The user selects a folder for write access through a separate macOS bookmark. The Repository read bookmark does not satisfy it. |
| `coding.apply_patch` | Effect | A user-started action checks the accepted decision, live write grant, path, file hash, permissions, and exact replacement before writing one file. It records the preimage and observed diff; Revert is a separate hash-checked action. |

Cable Propose Result → Proposal In, Proposal Out → Review In, Review Out → Apply In, and Write Scope → Apply Write. Press Apply explicitly after Accept. If the write grant is unavailable, Export Proposal remains available in Patch Proposal Inspector. Effect records live beside the board scene in `scene.json.patch-effects.json` (schema version 1), outside scene undo. The app makes no multi-file atomicity claim. Native macOS folder selection and write access still need hands-on acceptance on the release build.

The runner list is registered in app code. A user can compose and save kit arrangements today; declaring a new `toolName` in `kit.json` does not install a runner. Typed ports and a user-facing capability contract are planned in the [Phase 11 roadmap](phase_11_roadmap.md).

## First bounded check

Place **Check Spec**, **Run Check**, and **Check Result**. Select the trusted **Git diff --check** preset in Check Spec. Cable Spec → Run, Run → Result, and a separately selected **Write Scope** → Run Write. Select Run Check and press **Run Git diff check**; review the exact command, folder, and network statement before confirming. A Repository read grant, a stored folder path, or connected cables alone never starts the check.

The first command checks the unstaged Git diff for whitespace errors. Its result kit shows the exit category and whether the before/after Git status changed. Open the Check Result run ledger for redacted output, exact argv, cwd, environment key names, timing, exit code, truncation/cancellation, and Git state. You can cable Check Result → LLM Context so a later user-started model turn can read the short summary; the transcript stays in the ledger. The model cannot request a free-form shell command or start Run itself. The check process may have filesystem effects, so it requires Write Scope. Network access is allowed by the app sandbox; cwd is not isolation. Stop asks the native runner to terminate its process group and reports uncertainty if stopping cannot be verified. Exit 0 means only that this command exited 0. See [check execution](check_execution.md) for the signed macOS probe, bounds, and limits.
