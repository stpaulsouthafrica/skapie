# Kit packages

A **kit package** is a folder on disk under `kits/`. It is a recipe you can instantiate, not a second live scene. The scene document remains the source of truth for what is on the canvas. Instantiating still goes `KitApi` → `SceneStore.apply(SceneOp)` only.

A **kit** in memory is a `KitRecipe`. Saving writes a package; loading registers recipes into `KitApi`. See [glossary](glossary.md) and [kit API](kit_api.md).

## Layout

```
kits/
  README.md
  <kitId>/
    kit.json          # required
```

The folder name **must** match the `id` field in `kit.json`. A mismatch skips that package (load) or fails parse.

Optional later (not required now): `README.md`, `assets/`, `worker/`. Phase 7 does not read them.

## `kit.json` schema (v1)

```json
{
  "schemaVersion": 1,
  "id": "demo.note-card",
  "displayName": "Note card",
  "description": "Optional one-liner",
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
| `schemaVersion` | Required. Only `1` is supported. Other versions skip the package. |
| `id` | Required. Must match the folder name. No `/` or `\`. |
| `displayName` | Required. Maps to `KitRecipe.displayName`. |
| `description` | Optional. Package metadata; not stored on `KitRecipe`. |
| `capabilities` | Present as an empty-array seam. If non-empty: **warn and still load** `objects`. Workers are not implemented. |
| `objects` | Map 1:1 to `KitObjectSpec` (`typeId`, `x`, `y`, `width`, `height`, `props`). |

Unknown JSON fields are ignored. `objects[].typeId` must be a known registry type (`box`, `text`, `button`, `debug.rect`). Unknown type → skip that package with a log; never eval Dart.

Writes are pretty-printed JSON (2-space indent) so humans and agents can read them.

Built-in demo: `kits/demo.note-card/kit.json` (same numbers as the in-memory `demoNoteCardRecipe`).

## Kits root

Resolved with an absolute strategy (same spirit as the scene path). **Cwd is never the default.**

1. `--dart-define=SKAPIE_KITS_ROOT=/absolute/kits` (or env `SKAPIE_KITS_ROOT`)
2. `--dart-define=SKAPIE_PROJECT_ROOT=/absolute/repo` (or env) → `<repo>/kits`
3. Otherwise `<Application Support>/skapie/kits`

Relative override values are **rejected**: warning + Application Support fallback.

Startup logs the absolute kits root and how many packages loaded.

**macOS sandbox:** a debug/release sandboxed app cannot see the git repo `kits/` folder. Use an **absolute** `SKAPIE_KITS_ROOT` or `SKAPIE_PROJECT_ROOT`. If the resolved folder is missing or empty, `createAppKitApi` still registers the in-memory `demo.note-card` fallback so Add → note card works.

## Load and save

| API | Behavior |
|---|---|
| `KitApi.reloadPackages()` | `KitPackageStore.loadAll` scans `<root>/*/kit.json`, validates, registers. |
| `KitApi.saveKit(recipe)` | Writes `kits/<id>/kit.json` (creates the folder), then updates memory. |
| `KitApi.registerKit(recipe)` | Ephemeral in-memory only. Duplicate id still throws. Durable kits are saved packages. |

`KitPackageStore` is used only by `KitApi` (plus tests). UI and the future agent call `KitApi`, not the store.

**Conflict policy:** on load, each package is registered by id. If that id was already in memory, **disk replaces memory** (logged). The shelf is authoritative.

Bad packages (missing `schemaVersion`, id/folder mismatch, unknown `typeId`, unreadable JSON) are skipped with a clear log. Other packages still load.

## Dream goal (not scheduled)

Visible sub-agent kits: a future direction where a kit can show living agent work on the canvas (status, tokens, input/output). That implies sandboxed kit runtimes and permissions later. **Not Phase 7.** Phase 7 only ships declarative on-disk recipes. Planted seam: `capabilities: []` in `kit.json`.

## Not this phase

- Sandboxed workers, isolates, Wasm, or executing non-empty `capabilities`
- Git fetchers, marketplace, signing, or versioning beyond `schemaVersion`
- Agent harness / chat
- Hot-reload file watcher (startup load is enough)
- “Save selection as kit…” UI
- New registry widget types
- Batched multi-object undo
