# Kit packages

Each **kit package** is a folder `kits/<kitId>/` with required `kit.json`. The folder name must match `id` inside the file. Loading it creates a **kit recipe** in memory; instantiating uses that kit recipe, not a live re-read of the folder. See [glossary](../docs/glossary.md).

The git `kits/` tree is what you commit. A sandboxed app loads **Application Support** unless you set an absolute `SKAPIE_KITS_ROOT` or `SKAPIE_PROJECT_ROOT`. Details: [`docs/kit_packages.md`](../docs/kit_packages.md). Methods: [`docs/kit_api.md`](../docs/kit_api.md).

Demo kit package: [`demo.note-card/kit.json`](demo.note-card/kit.json).

Harness kit packages: [`harness.llm/kit.json`](harness.llm/kit.json), [`harness.system-prompt/kit.json`](harness.system-prompt/kit.json), [`harness.tools/kit.json`](harness.tools/kit.json).

Patch board packages: [`tools.propose_patch/kit.json`](tools.propose_patch/kit.json), [`coding.patch_proposal/kit.json`](coding.patch_proposal/kit.json), [`coding.review_decision/kit.json`](coding.review_decision/kit.json), [`coding.apply_patch/kit.json`](coding.apply_patch/kit.json).
