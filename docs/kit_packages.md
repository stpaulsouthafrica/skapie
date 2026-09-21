# Kit packages

A **kit package** is a folder on disk. It is not a second live scene. Loading it creates or updates a **kit recipe** in `KitApi`. Instantiating uses that in-memory kit recipe — it does not re-read the folder mid-turn. What you see on the canvas lives in the scene document. Load/save/instantiate go through `KitApi` — see the [Kit API reference](kit_api.md).

**Vocabulary:** **kit** vs **kit recipe** vs **kit package** — [glossary](glossary.md). Do not use bare “recipe.”

This file is the **only** `kit.json` schema. Do not invent a second one.

## Layout

```
kits/
  README.md
  <kitId>/
    kit.json          # required
```

Folder name **must** equal `id` inside `kit.json`. Mismatch → skip on load.

Optional later (not read today): `README.md`, `assets/`, `worker/`.

## `kit.json` schema (v1)

Matches [`kits/demo.note-card/kit.json`](../kits/demo.note-card/kit.json) and `parseKitPackageJson` in `lib/kit_api/kit_package.dart`.

```json
{
  "schemaVersion": 1,
  "id": "demo.note-card",
  "displayName": "Note card",
  "description": "A box with inset text.",
  "capabilities": [],
  "objects": [
    {
      "typeId": "box",
      "x": 0,
      "y": 0,
      "width": 200,
      "height": 88,
      "props": {}
    },
    {
      "typeId": "text",
      "x": 12,
      "y": 16,
      "width": 176,
      "height": 56,
      "props": { "content": "Note" }
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
| `objects` | 1:1 `KitObjectSpec`: `typeId`, `x`, `y`, optional `width` / `height` / `props`. |

Unknown JSON fields are ignored. `typeId` must be a registry type (`box`, `text`, `button`, `debug.rect`). Unknown type → skip that package; never eval Dart.

`saveKit` writes pretty JSON (2-space indent) via `KitApi.saveKit` — [method reference](kit_api.md#savekit).

## Where the app actually looks (read this)

There are **three** locations. They are not the same folder.

| Place | Path | Who uses it |
|---|---|---|
| **Git repo (what you commit)** | `<repo>/kits/<id>/kit.json` | Humans and git. Example: `kits/demo.note-card/`. |
| **Runtime default (what a sandboxed app loads)** | `<Application Support>/skapie/kits/` | `flutter run` with **no** override. On macOS debug that is inside the app **container**, not the repo. |
| **Override (make the app read the repo)** | Absolute `SKAPIE_KITS_ROOT` **or** `<SKAPIE_PROJECT_ROOT>/kits` | Developers who want the committed shelf. |

**Cwd is never the default.** Relative `SKAPIE_KITS_ROOT` is rejected (warning + Application Support).

Resolution order (`resolveKitsRoot` in `lib/kit_api/kit_path.dart`):

1. `--dart-define=SKAPIE_KITS_ROOT=/absolute/kits` (or env `SKAPIE_KITS_ROOT`) — must be absolute.
2. Else `--dart-define=SKAPIE_PROJECT_ROOT=/absolute/repo` (or env) → `/absolute/repo/kits`.
3. Else Application Support `…/skapie/kits`.

Startup logs the absolute kits root and how many packages loaded.

`saveKit` writes into **whichever root was resolved**, not “the git folder” unless that root *is* the repo.

```bash
# Default: Application Support (repo kits/ is invisible to the sandbox)
flutter run -d macos

# Load/save the committed repo shelf
flutter run -d macos \
  --dart-define=SKAPIE_PROJECT_ROOT=/Users/you/Development/skapie

# Or point straight at a kits directory
flutter run -d macos \
  --dart-define=SKAPIE_KITS_ROOT=/Users/you/Development/skapie/kits
```

If the resolved folder is empty or unreadable, `createAppKitApi` still has the in-memory `demo.note-card` fallback. After a successful disk load, **disk replaces memory** for that id ([`reloadPackages`](kit_api.md#reloadpackages)).

## Load and save

Call these on `KitApi`, not `KitPackageStore` (store is internal + tests).

| API | Behavior |
|---|---|
| [`reloadPackages`](kit_api.md#reloadpackages) | Scan `<root>/*/kit.json`. Skip bad packages. Disk replaces the in-memory kit recipe. |
| [`saveKit`](kit_api.md#savekit) | Write `<root>/<id>/kit.json`, then update the in-memory kit recipe. |
| [`registerKit`](kit_api.md#registerkit) | Ephemeral kit recipe. Duplicate id throws. |

**Conflict policy:** same id already in memory → disk wins (logged).

## Dream goal (not scheduled)

Visible sub-agent kits: a future direction where a kit can show living agent work on the canvas (status, tokens, input/output). That implies sandboxed kit runtimes and permissions later. The Phase 9 / 9.1 harness is **not** that. Planted seam: `capabilities: []` in `kit.json`.

## Not this phase

- Sandboxed workers, isolates, Wasm, or executing non-empty `capabilities`
- Git fetchers, marketplace, signing, or versioning beyond `schemaVersion`
- Agent chat / LLM HTTP — see [agent.md](agent.md); tool table: [kit_api.md](kit_api.md#agent-tools-phase-91)
- Hot-reload file watcher
- “Save selection as kit…” UI
- New registry widget types
- Batched multi-object undo
