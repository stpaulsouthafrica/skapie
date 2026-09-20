# Kit packages

Each installable kit is a folder `kits/<kitId>/` with required `kit.json`. The folder name must match `id` inside the file.

The git `kits/` tree is what you commit. A sandboxed app loads **Application Support** unless you set an absolute `SKAPIE_KITS_ROOT` or `SKAPIE_PROJECT_ROOT`. Details: [`docs/kit_packages.md`](../docs/kit_packages.md). Methods: [`docs/kit_api.md`](../docs/kit_api.md).

Demo: [`demo.note-card/kit.json`](demo.note-card/kit.json).
