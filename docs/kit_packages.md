# Kit packages

A **kit package** is a folder on disk. It is not a second live scene. Loading it creates or updates a **kit recipe** in `KitApi`. Instantiating uses that in-memory kit recipe — it does not re-read the folder mid-turn. What you see on the canvas lives in the scene document. Load/save/instantiate go through `KitApi` — see the [Kit API reference](kit_api.md).

**Vocabulary:** **kit** vs **kit recipe** vs **kit package** — [glossary](glossary.md). Do not use bare “recipe.”

This file is the **only** `kit.json` schema. Do not invent a second one.

## Layout

```
~/.skapie/kits/            # your shelf (default)
  <kitId>/
    kit.json               # required
    checklist.txt          # optional asset, listed in "assets"
```

Folder name **must** equal `id` inside `kit.json`. Mismatch → skip on load.

A package folder may hold anything the feature needs: extra docs, prompts, or text
files listed under `assets`. The user owns breakage in their own packages.

## `kit.json` schema (v1)

Matches [`kits/demo.note-card/kit.json`](../kits/demo.note-card/kit.json) and `parseKitPackageJson` in `lib/kit_api/kit_package.dart`.

```json
{
  "schemaVersion": 1,
  "id": "demo.checklist",
  "displayName": "Checklist",
  "description": "A doc-backed helper.",
  "capabilities": [],
  "ports": [
    { "id": "out", "value": "text", "flow": "output", "label": "Docs" }
  ],
  "assets": ["checklist.txt"],
  "objects": [
    {
      "typeId": "box",
      "x": 0,
      "y": 0,
      "width": 220,
      "height": 120,
      "props": { "skapieKit": "demo.checklist", "skapieRole": "frame" }
    },
    {
      "typeId": "text",
      "x": 12,
      "y": 40,
      "width": 196,
      "height": 48,
      "props": {
        "skapieKit": "demo.checklist",
        "skapieRole": "body",
        "contentRef": "checklist.txt"
      }
    }
  ]
}
```

| Field | Rule |
|---|---|
| `schemaVersion` | Required. Only `1`. Other versions skip the package. |
| `id` | Required. Same as folder name. No `/` or `\`. Not empty, `.`, or `..`. |
| `displayName` | Required. Maps to `KitRecipe.displayName`. |
| `description` | Optional. Disk metadata only — **not** on `KitRecipe`. `saveKit` omits it. |
| `capabilities` | Empty-array seam. If non-empty: **warn and still load** `objects`. No workers. |
| `ports` | Optional. Ports the package shows, from the host vocabulary. See below. |
| `assets` | Optional. Relative file paths in the package folder. Loaded at reload. |
| `objects` | 1:1 `KitObjectSpec`: `typeId`, `x`, `y`, optional `width` / `height` / `props`. |

Unknown JSON fields are ignored. `typeId` must be a registry type (`box`, `text`, `button`, `debug.rect`). Unknown type → skip that package; never eval Dart.

### Ports

A port picks a **host value**; a package cannot invent new kinds. Today one kind
is supported:

| `value` | Flow | Meaning |
|---|---|---|
| `text` | output | Carries the kit's body text (a doc-backed helper). |

A port has `id` (stable within the kit), `value`, `flow`, optional `label`, and
optional `placement` (`footer` or `middle`) and `side` (`left` or `right`).
Ports are stamped onto the frame when the kit is placed. Cable the `text` output
to an LLM **Context** or **Input** port and its body joins the request.

A package `tools.*` kit gets its grant ports from its `requiresRepository` /
`requiresWrite` props, exactly as before; `ports` adds to those.

### Assets and `contentRef`

`assets` lists files beside `kit.json`. On **Reload kit packages** the host reads
them. An object whose props carry `"contentRef": "checklist.txt"` gets its
`content` filled from that asset when the kit is placed. A missing asset is a
warning, not a crash. `saveKit` writes the asset files too.

`saveKit` writes pretty JSON (2-space indent) via `KitApi.saveKit` — [method reference](kit_api.md#savekit).

## Where the app actually looks (read this)

The product default is **your shelf**, `~/.skapie/kits`. The app creates it if
missing and, on first launch, copies the lean starter set into the user shelf.
Later launches never overwrite a package folder you already have.

| Place | Path | Who uses it |
|---|---|---|
| **User shelf (default)** | `~/.skapie/kits/<id>/kit.json` | The product. This is where new kits land. |
| **Git repo (reference)** | `<repo>/kits/<id>/kit.json` | Shipped starter sources and git. |
| **Project override** | `<SKAPIE_PROJECT_ROOT>/kits` | Developers reading the committed shelf. |
| **Explicit override** | absolute `SKAPIE_KITS_ROOT` | Tests and demos that must not touch the home shelf. |

**Cwd is never the default.** A relative `SKAPIE_KITS_ROOT` is rejected with a
warning and ignored.

Resolution order (`resolveKitsRoot` in `lib/kit_api/kit_path.dart`):

1. `--dart-define=SKAPIE_KITS_ROOT=/absolute/kits` (or env `SKAPIE_KITS_ROOT`) — must be absolute.
2. Else `--dart-define=SKAPIE_PROJECT_ROOT=/absolute/repo` (or env) → `/absolute/repo/kits`.
3. Else `~/.skapie/kits` (or Application Support if there is no home folder).

Startup logs the absolute kits root, its source, and how many packages loaded.

`saveKit` writes into **whichever root was resolved**, which is the user shelf by default.

```bash
# Default: the user shelf ~/.skapie/kits (seeded once)
flutter run -d macos

# Read the committed repo shelf instead
flutter run -d macos \
  --dart-define=SKAPIE_PROJECT_ROOT=/Users/you/Development/skapie

# Point straight at any kits directory
flutter run -d macos \
  --dart-define=SKAPIE_KITS_ROOT=/Users/you/Development/skapie/kits
```

If the resolved folder is empty or unreadable, `createAppKitApi` still has in-memory demo, board, harness, Repository, and tool-kit fallbacks. After a successful disk load, **disk replaces memory** for that id ([`reloadPackages`](kit_api.md#reloadpackages)).

## Load and save

Call these on `KitApi`, not `KitPackageStore` (store is internal + tests).

| API | Behavior |
|---|---|
| [`reloadPackages`](kit_api.md#reloadpackages) | Scan `<root>/*/kit.json`. Skip bad packages. Disk replaces the in-memory kit recipe. |
| [`saveKit`](kit_api.md#savekit) | Write `<root>/<id>/kit.json`, then update the in-memory kit recipe. |
| [`registerKit`](kit_api.md#registerkit) | Ephemeral kit recipe. Duplicate id throws. |

**Conflict policy:** same id already in memory → disk wins (logged).

## Current capability boundary

`coding.repository` and the four starter tools (`tools.read`, `tools.write`, `tools.edit`, `tools.shell`) are ordinary package recipes. Their native folder permission and runners are implemented by the host app. A package with an unknown `toolName` does not become executable. The old `tools.repo_*` and kit-author world tools now live under [`examples/kits/`](../examples/README.md). See [tool kits](tools.md) and the [Phase 12 inventory](phase_12_inventory.md).

A package can name a port from the host vocabulary and can request a tool the
host already runs. Anything harder needs a **host KitApi hook**, added on purpose
and documented — not a new first-party product kit.

## MCP and other hard packages

MCP is a **package**, not a host feature. Phase 13 ships no MCP kit on the
starter shelf. A user or example may author one later; the host only grows an MCP
hook if a spike proves one is required. The same rule covers marketplaces,
signing, and swarm UIs.

## Later direction

Visible sub-agent kits: a future direction where a kit can show living agent work on the canvas (status, tokens, input/output). That implies sandboxed kit runtimes and permissions later. The Phase 9 / 9.1 harness is **not** that. Planted seam: `capabilities: []` in `kit.json`.

## Not this phase

- Sandboxed workers, isolates, Wasm, or executing non-empty `capabilities`
- Git fetchers, marketplace, signing, or versioning beyond `schemaVersion`
- Agent chat / LLM HTTP — see [agent.md](agent.md); tool table: [kit_api.md](kit_api.md#agent-tools-phase-91)
- Hot-reload file watcher
- “Save selection as kit…” UI
- New registry widget types
- Batched multi-object undo
