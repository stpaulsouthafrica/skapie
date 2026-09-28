# Author a kit package

A kit package is a folder `~/.skapie/kits/<id>/` with one required file,
`kit.json`. You do not need to rebuild the app to add one. Write the folder, run
**Reload kit packages**, place the kit on the board, then cable it.

The app creates `~/.skapie/kits` and copies the starter set in on first launch.
Later launches keep your edits. No network is used. This file, [Kit API](kit_api.md),
and [Kit packages](kit_packages.md) ship inside the app.

## `kit.json`

| Field | Rule |
| --- | --- |
| `schemaVersion` | Required. Only `1`. |
| `id` | Required. Same as the folder name. |
| `displayName` | Required. Shown on the card. |
| `description` | Optional. A short note. |
| `capabilities` | Optional seam. Leave `[]`. |
| `ports` | Optional. Ports the kit shows; see [ports](kit_packages.md#ports). |
| `assets` | Optional. Relative files in the folder, read on reload. |
| `objects` | Required. One entry per drawn object. |

Each object has `typeId`, `x`, `y`, and optional `width`, `height`, `props`.

Allowed `typeId` values come from the registry: `box`, `text`, `button`, `debug.rect`. An unknown `typeId` skips the whole package.

## Minimal example

```json
{
  "schemaVersion": 1,
  "id": "demo.hello",
  "displayName": "Hello",
  "description": "A box with one line of text.",
  "capabilities": [],
  "objects": [
    { "typeId": "box", "x": 0, "y": 0, "width": 200, "height": 80, "props": {} },
    { "typeId": "text", "x": 12, "y": 16, "width": 176, "height": 48, "props": { "content": "Hello" } }
  ]
}
```

## Make it useful

Two ways a package carries real behavior with no app rebuild:

1. **A doc-backed helper.** Add an `assets` file and a `contentRef` prop, plus a
   `text` output port. Cable the output to an LLM **Context** port and its text
   joins the request. Example in [Kit packages](kit_packages.md#assets-and-contentref).
2. **A tool.** Name a host runner with `props.toolName`; see below.

Ports come from the package and are stamped onto the frame when you place it.

## Reload, place, and cable

1. Write `~/.skapie/kits/<id>/kit.json` (and any assets).
2. Run **Reload kit packages** from the command palette.
3. Add the kit from the palette. It appears because it is now a registered recipe.
4. Cable it to other kits. Every kit keeps its look and its ports in the package.

If the folder name and `id` do not match, the package is skipped.

## Tools and grants

A tool package has two files. `kit.json` is the card. `kit.dart` is the program.
On launch, and again on **Reload kit packages**, the app runs `register()` from
`kit.dart`. Copy the folder into `~/.skapie/kits` and the next launch uses it.
No app rebuild.

```dart
import 'package:skapie_kit/host.dart';

void register() {
  addTool(
    'list_kits',
    'List registered kits.',
    '{"type":"object","properties":{},"additionalProperties":false}',
  );
}

String runTool(String name, String argsJson, String contextJson) {
  return call('listKits', argsJson);
}
```

`call` names a host hook, such as `listKits`, `addObject`, `getKit`, or
`registerKit`. `saveKit` and `reloadPackages` are deferred: return
`{"__defer":"saveKit","args":...}` or `{"__defer":"reloadPackages"}`. A hook the
host does not know is refused.

Give the kit an id that starts with `tools.` and set `props.toolName` to the
same name you pass to `addTool`. Cable the card's Output to the LLM Tools port.

The starter shelf still ships four host runners: `read`, `write`, `edit`, and
`shell`. Read needs the Repository read folder. Write, edit, and shell need the
Repository write folder.

## Author from inside the app

The starter tools can write the shelf themselves. Double-click the Repository
kit and choose `~/.skapie/kits` as both the read and write folder. Then the
agent's Read/Write/Edit/Shell tools may create and edit `<id>/kit.json` and its
assets there. Create the folder first (for example Shell: `mkdir -p <id>`), then
write the files. Run **Reload kit packages**, then place and cable the new kit.
No app rebuild is involved.

## When a kit is broken

Package load faults and grant/tool denials show in the top-left host status
while there is an error. A bad `kit.json` shows as a skipped package with the
reason; fixing it and reloading clears the note. The app keeps running.

## Where the app looks

The default shelf is `~/.skapie/kits`. See [Kit packages](kit_packages.md) for
the full rule.

| Place | Path |
| --- | --- |
| User shelf (default) | `~/.skapie/kits/<id>/kit.json` |
| Git repo (reference) | `<repo>/kits/<id>/kit.json` |
| Project override | `<SKAPIE_PROJECT_ROOT>/kits` |
| Explicit override | absolute `SKAPIE_KITS_ROOT` |
