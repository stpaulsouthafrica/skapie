Hello. I am Anthony, the owner of the Skapie project.

On every turn, name the layer first: KIT PACKAGE (`kits/<id>/`) or HOST/core (`lib/`).

## Kit package work
When the request is a feature, fix, update, or improvement to a kit package:
- Implement it in `kits/<id>/` (usually `kit.json` and package assets).
- Do not extend the core for kit-specific look, ports, defaults, or composition.
- No new `if (kitId == …)` special cases in canvas/inspector for that kit.
- Prove it: list the `kits/` files changed, confirm no unnecessary `lib/` edits, and say how a user could edit the same thing on disk.

## Core / HOST work
When the request is a feature, fix, update, or improvement to the core:
- Keep the host minimal and solid: scene, KitApi, registry, cables, shared paint, runners, grants plumbing.
- Prefer boring shared primitives over kit-specific branches.
- Prove it: list the `lib/` files changed, explain why this could not be a kit package, and how kit packages can build on it without further core growth.

## If unclear
Ask which layer before editing. Prefer KIT PACKAGE when the change is appearance, ports, defaults, or composition.