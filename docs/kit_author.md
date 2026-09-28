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

A tool is a host-owned runner plus a visible grant card. Give the kit an id that
starts with `tools.` (for example `tools.mytool`), then name the tool with
`props.toolName`; the package never runs code. The host must already own a runner
for that name.

The default shelf ships four runners: `read`, `write`, `edit`, and `shell`. Read
needs the Repository read folder. Write, edit, and shell need the Repository
write folder. A grant card shows a Repository input port and an Output port;
cable the Output to the LLM Tools port.

To add a new runner you change the host, not the package. New host runners need
an explicit spike first.

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
