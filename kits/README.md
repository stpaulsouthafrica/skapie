# Kit packages

Each **kit package** is a folder `kits/<kitId>/` with required `kit.json`. The folder name must match `id` inside the file. Loading it creates a **kit recipe** in memory; instantiating uses that kit recipe, not a live re-read of the folder. See [glossary](../docs/glossary.md).

This shelf is the default install. It holds only the lean starter:

- `harness.llm`, `harness.conversation` — the model and its thread
- `coding.repository` — one card with separate read and write folder grants
- `tools.read`, `tools.write`, `tools.edit`, `tools.shell` — the four coding tools
- `skapie.extensions` — offline pointers to the kit-author docs
- `demo.note-card` — a schema example, not on the palette

Everything else is a user package. Demoted first-party kits (checks, Propose/Review/Apply, Write Scope, Run Control, the kit-author world tools) live under [`examples/kits/`](../examples/README.md) as rebuild references. They are off the palette and off the starter.

This tree is the shipped starter source and a reference. The product default is
the **user shelf** `~/.skapie/kits`, seeded from this lean set on first launch.

A package folder may hold extra files listed under `assets`. A package can declare
its own `ports` and can name a host tool runner. Details: [`docs/kit_packages.md`](../docs/kit_packages.md). Methods: [`docs/kit_api.md`](../docs/kit_api.md).
