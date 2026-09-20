# Kit packages

Each installable kit is a folder `kits/<kitId>/` with required `kit.json`. The folder name must match `id` inside the file.

Phase 7 loads these packages into `KitApi` at startup (`reloadPackages`) and can write them (`saveKit`). The scene is still the live source of truth; packages are recipes.

Contract, schema, kits root / `SKAPIE_KITS_ROOT`, and conflict policy (disk replaces memory): [`docs/kit_packages.md`](../docs/kit_packages.md). Kit API: [`docs/kit_api.md`](../docs/kit_api.md).

Demo: [`demo.note-card/kit.json`](demo.note-card/kit.json).
