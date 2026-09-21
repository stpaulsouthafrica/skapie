# Kit API

`KitApi` is the **only high-level door** into the scene. It does not keep a second object list. Every scene change wraps `SceneStore.apply(SceneOp)`.

UI, tests, and a future agent should call `KitApi`. Do not call `store.apply` from app code. Do not eval Dart. Do not invent widgets.

On-disk folders are documented in [kit packages](kit_packages.md). Types are documented in [registry](registry.md). Words: [glossary](glossary.md). Session loop: [agent.md](agent.md).

**Vocabulary:** a **kit** is what you instantiate; a **kit recipe** (`KitRecipe`) is the in-memory definition; a **kit package** is the on-disk `kits/<id>/` folder. Do not use bare “recipe.” See [glossary](glossary.md).

## Mental model

| Thing | What it is | Source of truth? |
|---|---|---|
| **Scene object** | One typed item on the canvas (`id`, `type`, frame, `props`) | **Yes** — the scene document |
| **Kit** (as `KitRecipe`) | In-memory kit recipe: id + display name + relative `KitObjectSpec`s | Process memory |
| **Kit package** | Folder `kits/<kitId>/kit.json` | Disk shelf (not a live world) |
| **Registry** | `typeId` → builder (`box`, `text`, `button`, `debug.rect`) | Known widgets only |

Instantiating a kit **copies** specs into new scene objects. Editing those objects does not edit the kit. Reloading the scene does not reload kits; kits reload from disk via `reloadPackages`.

`registerKit` is ephemeral. `saveKit` is durable. On load, **disk replaces memory** for the same id.

## Lifecycle

App bootstrap (`lib/main.dart`):

1. `bootstrapSceneStore()` loads `scene.json`.
2. `bootstrapKitApi()` resolves the kits root (see [kit packages](kit_packages.md)).
3. `createAppKitApi(...)` constructs `KitApi` and registers `demoNoteCardRecipe` plus the harness kit recipes (`harness.llm`, `harness.system-prompt`, `harness.tools`) as fallbacks.
4. `await reloadPackages()` — disk packages win when present.
5. UI / future agent call `listKits`, `instantiate`, `addObject`, `saveKit`, …

```dart
final api = createAppKitApi(
  store: store,
  registry: registry,
  packages: KitPackageStore(root: kitsRoot, registry: registry),
);
api.log = debugPrint;
await api.reloadPackages();
```

Tests may omit `packages`. Then `reloadPackages` is a no-op and `saveKit` throws.

## Types

### `KitObjectSpec`

Relative object inside a kit recipe. World position at instantiate is `origin + (x, y)`.

| Field | Type | Notes |
|---|---|---|
| `typeId` | `String` | Must be a registry type at instantiate / save |
| `x`, `y` | `double` | Offset from instantiate origin |
| `width`, `height` | `double?` | If null, `addObject` uses `defaultObjectSize(typeId)` |
| `props` | `Map<String, Object?>` | Merged over registry defaults. Text uses `content`, not `text` |

### `KitRecipe`

| Field | Type |
|---|---|
| `id` | `String` — e.g. `demo.note-card` |
| `displayName` | `String` |
| `objects` | `List<KitObjectSpec>` |

`description` exists on disk `kit.json` only. It is **not** a `KitRecipe` field. `saveKit` does not write `description`.

### Built-in sizes (`defaultObjectSize`)

Used when `width` / `height` are omitted:

| `typeId` | Size |
|---|---|
| `box` | 160×100 |
| `text` | 220×48 |
| `button` | 140×40 |
| `debug.rect` | 120×80 |
| anything else | 120×80 |

## Method reference

Constructor: `KitApi({required SceneStore store, required ObjectRegistry registry, KitPackageStore? packages})`.

Public fields: `store`, `registry`, `packages`, `log` (`void Function(String message)?` — load/save diagnostics).

### `addObject`

```dart
String addObject({
  required String typeId,
  double x = 0,
  double y = 0,
  double? width,
  double? height,
  Map<String, Object?> props = const {},
})
```

Insert one scene object. Generates an id (`o…`). Merges `props` over registry `defaultProps`. Missing size → `defaultObjectSize`.

- **Returns:** new scene object id.
- **Applies:** `AddObject` (one undo step if the document changed).
- **Throws:** `ArgumentError` (`Unknown typeId: …`). Scene unchanged.

### `removeObject`

```dart
void removeObject(String id)
```

- **Applies:** `RemoveObject`. Missing id → store no-op, **no** undo step.

### `updateFrame`

```dart
void updateFrame({
  required String id,
  double? x,
  double? y,
  double? width,
  double? height,
  double? rotation,
})
```

Patch any listed frame fields. Omitted fields stay. `rotation` is radians around the frame center.

- **Applies:** `UpdateObjectFrame`. Missing id or unchanged frame → no-op, no undo.

### `updateProps`

```dart
void updateProps(String id, Map<String, Object?> patch)
```

**Shallow merge.** Listed keys overwrite; others stay. A `null` value **removes** that key.

- **Applies:** `UpdateObjectProps`. Missing id or unchanged props → no-op, no undo.

### `setLocked`

```dart
void setLocked(String id, bool locked)
```

Sets `SceneObject.locked` (not a prop). Locked objects can be selected and deleted; they cannot be moved.

- **Applies:** `SetObjectLocked`. Missing id or already that value → no-op, no undo.

### `registerKit`

```dart
void registerKit(KitRecipe recipe)
```

In-memory only. Does not write disk. Does not mutate the scene.

- **Throws:** `StateError` (`Duplicate kit id: …`).
- **Undo:** none.

Prefer `saveKit` for anything that should survive restart. `reloadPackages` may **replace** this kit recipe if a package has the same id.

### `getKit`

```dart
KitRecipe? getKit(String kitId)
```

Lookup. `null` if unknown. No I/O, no scene change.

### `listKits`

```dart
List<KitRecipe> listKits()
```

Unmodifiable snapshot of in-memory kit recipes (insertion order). The Add menu uses this (demo id labeled **Demo kit: note card**).

### `instantiate`

```dart
List<String> instantiate(String kitId, {required Offset origin})
```

Validate **every** spec `typeId` first, then `addObject` for each spec. Spec `(x, y)` is added to `origin` (world). The Add menu passes the camera offset (world point at viewport center).

- **Returns:** new scene object ids, same order as the kit recipe.
- **Undo:** N objects = **N undo steps** (v1). Not one batched undo.
- **Throws:** `ArgumentError` (`Unknown kit: …`) or `ArgumentError` (`Unknown typeId: …`) **before** any apply. No partial spawn.

### `reloadPackages`

```dart
Future<void> reloadPackages()
```

Scan the kits root (`*/kit.json`), parse, register. See [kit packages](kit_packages.md).

- If `packages` is null: return immediately.
- **Conflict:** disk **replaces** memory for the same id (logged).
- Bad packages: skip + `log`; other packages still load.
- Non-empty `capabilities`: warning, objects still load. Workers are not run.
- Does not mutate the scene.
- **Undo:** none.

### `saveKit`

```dart
Future<void> saveKit(KitRecipe recipe)
```

Write pretty `kit.json` under the **resolved** kits root (`<root>/<id>/kit.json`), create the folder, then put the kit recipe in memory (overwrite ok).

Writes to Application Support unless you overrode the root. It does **not** automatically write the git repo `kits/` folder. Path rules: [kit packages](kit_packages.md).

- **Throws:** `StateError` (`No kit package store`); `ArgumentError` invalid id (`/`, `\`, empty, `.`, `..`) or unknown `typeId` in objects.
- Does not mutate the scene.
- **Undo:** none (disk kit package + in-memory kit recipe only).

### `createAppKitApi`

```dart
KitApi createAppKitApi({
  required SceneStore store,
  ObjectRegistry? registry,
  KitPackageStore? packages,
})
```

Uses `createBuiltinRegistry()` if `registry` is omitted. Always registers `demoNoteCardRecipe` and the harness kit recipes. Call `reloadPackages` afterward so disk wins.

## Errors

| Situation | Result |
|---|---|
| Unknown `typeId` in `addObject` / `instantiate` / `saveKit` | `ArgumentError`; scene unchanged (instantiate validates first) |
| Unknown `kitId` in `instantiate` | `ArgumentError` (`Unknown kit: …`) |
| Duplicate `registerKit` id | `StateError` |
| `saveKit` with no `packages` | `StateError` (`No kit package store`) |
| Invalid kit id on write | `ArgumentError` |
| Bad `kit.json` on load | That package skipped; logged; others load |
| Relative `SKAPIE_KITS_ROOT` | Warning; fall back to Application Support |
| Unreadable kits root (sandbox) | Load errors logged; in-memory demo fallback remains |

## Cookbook

Assume `kitApi` is a constructed `KitApi`. All snippets go through `KitApi` only.

### Add a box

```dart
final id = kitApi.addObject(typeId: 'box', x: 40, y: 80);
```

### Add text with content

```dart
kitApi.addObject(
  typeId: 'text',
  x: 12,
  y: 16,
  props: {'content': 'Hello'},
);
```

### Instantiate the demo kit

```dart
kitApi.instantiate(
  'demo.note-card',
  origin: const Offset(100, 50),
);
// Undo twice to remove both objects (box + text).
```

### Update props, lock, delete

```dart
kitApi.updateProps(id, {'content': 'Edited'});
kitApi.setLocked(id, true);
kitApi.removeObject(id);
```

### Move (one undo)

```dart
kitApi.updateFrame(id: id, x: 200, y: 40);
```

### Save a new kit, then instantiate (golden)

Writes `demo.two-boxes` to the **resolved** kits root, then spawns it.

```dart
await kitApi.saveKit(
  const KitRecipe(
    id: 'demo.two-boxes',
    displayName: 'Two boxes',
    objects: [
      KitObjectSpec(typeId: 'box', x: 0, y: 0, width: 80, height: 48),
      KitObjectSpec(typeId: 'box', x: 96, y: 0, width: 80, height: 48),
    ],
  ),
);

final ids = kitApi.instantiate(
  'demo.two-boxes',
  origin: const Offset(0, 0),
);
// ids.length == 2; undo twice to remove them.
```

Reload in a fresh `KitApi` pointing at the same root:

```dart
await otherApi.reloadPackages();
otherApi.getKit('demo.two-boxes'); // non-null
```

### List kits for a menu

```dart
for (final kit in kitApi.listKits()) {
  // kit.id, kit.displayName
}
```

## Agent tools (Phase 9.1)

Implemented by `createKitAgentTools` + `AgentToolDispatcher` inside `AgentSession`. The harness calls `KitApi` methods; it does not poke `SceneStore` fields. Overlay chat and HTTP live in [agent.md](agent.md).

| Tool name | Maps to | Args (conceptual JSON) | Notes |
|---|---|---|---|
| `list_kits` | `listKits` | `{}` | Returns `{id, displayName}[]` |
| `get_kit` | `getKit` | `{ "kitId": "demo.note-card" }` | Null → unknown kit |
| `instantiate_kit` | `instantiate` | `{ "kitId": "demo.note-card", "originX": 0, "originY": 0 }` | N undos |
| `add_object` | `addObject` | `{ "typeId": "box", "x": 0, "y": 0, "width": 160, "height": 100, "props": {} }` | Returns `{ "id": "o…" }` |
| `remove_object` | `removeObject` | `{ "id": "o1" }` | Missing id is a no-op |
| `update_frame` | `updateFrame` | `{ "id": "o1", "x": 10, "y": 20, "width": null, "height": null, "rotation": null }` | Omit or null = leave unchanged |
| `update_props` | `updateProps` | `{ "id": "o1", "patch": { "content": "Hi" } }` | `null` value deletes a key |
| `set_locked` | `setLocked` | `{ "id": "o1", "locked": true }` | |
| `save_kit` | `saveKit` | `{ "id": "demo.two-boxes", "displayName": "Two boxes", "objects": [ { "typeId": "box", "x": 0, "y": 0, "width": 80, "height": 48 } ] }` | Writes disk at resolved kits root |
| `reload_packages` | `reloadPackages` | `{}` | Disk replaces memory |
| `register_kit` | `registerKit` | same shape as `save_kit` | Ephemeral; prefer `save_kit` |

Unknown `typeId` / unknown kit → tool error, scene unchanged.

## Demo kits

`demo.note-card` (`demoNoteCardKitId`): `box` 200×88 + inset `text` (`content`: `Note`). Shipped as [`kits/demo.note-card/kit.json`](../kits/demo.note-card/kit.json).

## Harness kits

Ordinary kits. They are the visible first principles of the agent harness. See [agent.md](agent.md) and [glossary](glossary.md).

| Id | Package | This phase |
|---|---|---|
| `harness.llm` | [`kits/harness.llm/kit.json`](../kits/harness.llm/kit.json) | Latest vanilla turn via `publishLlmKit` |
| `harness.system-prompt` | [`kits/harness.system-prompt/kit.json`](../kits/harness.system-prompt/kit.json) | Stub. Editable text. `attachedTo` reserved. |
| `harness.tools` | [`kits/harness.tools/kit.json`](../kits/harness.tools/kit.json) | Stub. Tool names as text. `attachedTo` reserved. |

`createAppKitApi` registers all of these as kit recipes; a loaded package replaces the matching id. No animation.

## Dream goal (not scheduled)

Visible sub-agent kits: a future direction where a kit can show living agent work on the canvas (status, tokens, input/output). That implies sandboxed kit runtimes and permissions later. The Phase 9 harness is **not** that. Planted seam: `capabilities: []` in `kit.json`. See [kit packages](kit_packages.md) and [agent.md](agent.md).

## Non-goals

- Workers, isolates, Wasm, executing non-empty `capabilities`
- Streaming / Pi / MCP (see [agent.md](agent.md) — tools are 9.1; provider + chat are 9.2)
- Dart eval / new registry types
- Batched multi-object undo
- “Save selection as kit…” UI
- File watcher (startup `reloadPackages` is enough)
