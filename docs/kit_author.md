# Author a kit package

A kit package is a folder `kits/<id>/` with one required file, `kit.json`. You do not need to rebuild the app to add one. Write the folder, reload packages, place the kit on the board, then cable it.

No network is used. This file, [Kit API](kit_api.md), and [Kit packages](kit_packages.md) ship inside the app.

## `kit.json`

| Field | Rule |
| --- | --- |
| `schemaVersion` | Required. Only `1`. |
| `id` | Required. Same as the folder name. |
| `displayName` | Required. Shown on the card. |
| `description` | Optional. A short note. |
| `capabilities` | Optional seam. Leave `[]`. |
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

## Reload, place, and cable

1. Write `kits/<id>/kit.json`.
2. Run **Reload kit packages** from the command palette.
3. Add the kit from the palette. It appears because it is now a registered recipe.
4. Cable it to other kits. Every kit keeps its look and its ports in the package.

If the folder name and `id` do not match, the package is skipped.

## Tools and grants

A tool is a host-owned runner plus a visible grant card. The package names the tool with `props.toolName`; it never runs code. The host must already own a runner for that name.

The default shelf ships four runners: `read`, `write`, `edit`, and `shell`. Read needs the Repository read folder. Write, edit, and shell need the Repository write folder. A grant card shows a Repository input port and an Output port; cable the Output to the LLM Tools port.

To add a new runner you change the host, not the package. New host runners need an explicit spike first.

## Where the app looks

Three locations exist. See [Kit packages](kit_packages.md) for the full rule.

| Place | Path |
| --- | --- |
| Git repo | `<repo>/kits/<id>/kit.json` |
| Runtime default | `<Application Support>/skapie/kits/` |
| Override | absolute `SKAPIE_KITS_ROOT` or `<SKAPIE_PROJECT_ROOT>/kits` |
