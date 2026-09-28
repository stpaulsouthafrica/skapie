# Phase 13 — injectable packages so future work happens inside Skapie

Status: **implemented**. Follows [Phase 12](phase_12.md). Older sketches: [archive/phase_13_extensible_kits.md](archive/phase_13_extensible_kits.md) (historical only).

Evidence:
- Shelf + seed + overrides: `lib/kit_api/kit_path.dart`, `lib/kit_api/kit_seed.dart`, `lib/main.dart` (`bootstrapKitApi`); tests `test/kit_api/kit_shelf_test.dart`.
- Package behavior (ports, assets, tool registration): `lib/kit_api/kit_package_ports.dart`, `lib/kit_api/kit_package.dart`, `lib/kit_api/kit_package_store.dart`, `lib/canvas/kit_port_descriptor.dart`, `lib/canvas/kit_ports.dart`; tests `test/kit_api/kit_package_behavior_test.dart`.
- Host status for faults and denials: `lib/kit_api/host_status.dart`, `lib/app/host_status_banner.dart`, `lib/agent/agent_controller.dart`; tests `test/app/host_status_test.dart`, `test/app/host_status_banner_test.dart`.
- Gate proof: `test/app/phase_13_proof_test.dart` (empty board, seeded starter edit, LLM authors `demo.checklist` on the shelf and its text reaches the request). Docs: [kit_author](kit_author.md), [kit_packages](kit_packages.md), [kit_api](kit_api.md).

## Why this phase exists

After Phase 13, Anthony should make **future code and feature changes inside the Skapie app** (edit/create packages under `~/.skapie/kits`, reload, place, cable) — not by asking agents to grow first-party Dart product kits in `lib/`.

Phase 13 builds the Pi-like loop that makes that true: user kits shelf, rich KitApi, reload inject, status on faults, and a starter LLM that can author useful kits from local docs.

## Agent instruction (whole phase)

You are implementing **all of Phase 13**. Do not wait for a per-slice paste. Work **in order** through every numbered slice below. Finish and prove each slice’s **How to test** before starting the next. Stay on `main`. Do not invent product kits. Do not ship MCP (or similar) as a first-party kit.

**Lead every turn with:**

- Layer: `KIT PACKAGE` | `HOST` (`lib/`) | `GRANT` | `BOARD`
- Kit id (if any)
- One-sentence Change
- Stop after this layer (one slice’s layer of work per turn when possible)
- Acceptance: package shelf vs `lib/`; no new first-party feature kits; justify any HOST / KitApi growth

**Paste prompt (give the agent this whole file):**

```
Read and implement docs/phase_13.md end-to-end.

Work slices in order (13.0 → 13.5). Prove each How to test before the next.
Layer vocabulary: KIT PACKAGE | HOST | GRANT | BOARD on every turn.
End state: future features are packages on ~/.skapie/kits that inject without Flutter rebuild / without host feature kits.
Host may grow KitApi hooks when a spike proves they are required; never grow optional product kits (MCP etc.).
Errors: existing top-left host status only when there is an error (package faults + grant/tool denials).
Phase gate: starter LLM authors a useful kit into ~/.skapie/kits, reload, place, use — no Flutter rebuild, no host change for that package.
Stay on main. Sheep emoji when the phase gate passes.
```

**Status:** implemented. Every slice below is done; the phase gate at the bottom is checked off.

## North star and fence

| In | Out |
| --- | --- |
| `~/.skapie/kits` as default shelf; seed full starter set once | Marketplace, signing |
| Rich KitApi so packages can do hard jobs | Shipped MCP (or similar) product kit |
| Reload inject without Flutter rebuild | Swarms / pause-resume product UI |
| Top-left host status for package + grant/tool faults | New first-party feature kits in Dart |
| Offline docs + starter LLM authoring gate | Eval corpus as a phase deliverable |

**Slim product** means: no optional kits/tools users may not want. The **host** may be as large as needed for hooks and APIs.

**Package folder** may contain whatever the feature needs (metadata, assets, prompts, docs, injectable behavior). User owns breakage.

## Locked decisions

| Topic | Decision |
| --- | --- |
| End of phase | Future work is done inside Skapie via packages on the user shelf |
| Kits root | `~/.skapie/kits` (create if missing). `SKAPIE_KITS_ROOT` for tests/demos |
| Seed | First launch copies the **full lean starter set** into the shelf; later launches do not clobber user edits |
| New kits | Land under `~/.skapie/kits/<id>/` |
| Repo `kits/` / `examples/kits/` | Ship/dev references; product prefers user shelf after seed |
| KitApi | Packages implement features; host grows APIs only via justified spikes |
| Errors | Existing top-left status; only when there is an error |
| Useful kit (gate) | Ports/props from package + real behavior against KitApi (small tool/helper OK). MCP not required for the gate |
| Layer vocabulary | Required every agent turn |

Carry forward from Phase 12: context provenance stays in host; demoted flows stay examples / [rebuild notes](phase_12_rebuild_notes.md) — not Phase 13 product kits. Inventory: [phase_12_inventory.md](phase_12_inventory.md).

## Product outcome (what must exist when the phase gate passes)

1. Default install uses `~/.skapie/kits` with starter packages seeded once.
2. KitApi + local author docs are enough for human or starter LLM to create packages offline.
3. Reload registers new/changed packages without a Flutter rebuild.
4. Package load/register/runtime faults and grant/tool denials show in top-left host status only when needed.
5. Starter LLM can create a useful kit into the shelf, reload, place, cable, and use it with **no host change for that package**.
6. Anthony can treat “change the product” as “edit/create a kit in the app/shelf,” not “add a Dart feature kit.”

---

## 13.0 — freeze the cut

### 13.0.1 — docs point here as active work

- **What this is.** `docs/README.md`, Phase 12 handoff, and roadmap treat Phase 13 as the active implement plan (this file).
- **How to test.** Those docs link to this file; archive Phase 13 is marked historical only.
- **Done when.** Links and status wording match; no conflicting “wait to rewrite Phase 13” language left in active docs.

### 13.0.2 — whole-phase handoff is this document

- **What this is.** This file is the single implement brief. AGENTS.md (if present) still leads with Layer.
- **How to test.** An implementer reading only this file knows order, fence, and gate without another paste.
- **Done when.** No dependency on “implement only slice N” from an external chat for Phase 13 to proceed.

## 13.1 — user kits shelf

### 13.1.1 — default root `~/.skapie/kits`

- **What this is.** Host resolves `~/.skapie/kits`, creates it if missing, and loads packages from it when no override is set.
- **How to test.** Launch without `SKAPIE_KITS_ROOT`; shelf path resolves; directory exists after launch.
- **Done when.** Product default is the user shelf, not only repo `kits/`.

### 13.1.2 — seed full starter set once

- **What this is.** First launch copies the lean starter packages (input/LLM/conversation/output/repository/Read/Write/Edit/Shell/Skapie Extensions — same set as Phase 12 starter) into `~/.skapie/kits`. Second launch must not overwrite user edits.
- **How to test.** Fresh profile gets starter folders; edit a seeded `kit.json`, relaunch, edit preserved; reload shows the edit.
- **Done when.** Seeded shelf is source of truth for those kit ids after first seed.

### 13.1.3 — `SKAPIE_KITS_ROOT` override

- **What this is.** Tests/demos can point at another shelf (repo `kits/`, `examples/kits/`, temp dir).
- **How to test.** Automated tests use an override path; product default unchanged when unset.
- **Done when.** CI/tests do not require writing into the developer’s real home shelf.

### 13.1.4 — create / reload / place on the shelf

- **What this is.** Validate → write `~/.skapie/kits/<id>/` → reload → place → cable. No Flutter rebuild for package description and for injectable content KitApi supports.
- **How to test.** Add a trivial package by hand; reload; it appears; ports/look from package; no `lib/` change for that package.
- **Done when.** Manual create path works on the user shelf.

## 13.2 — KitApi surface

### 13.2.1 — document the stable KitApi for authors

- **What this is.** Update [kit_api.md](kit_api.md), [kit_packages.md](kit_packages.md), and [kit_author.md](kit_author.md) so they describe the user shelf, seed, reload, assets/injectable behavior, grants, tool registration, and reporting faults to host status. One `kit.json` schema story.
- **How to test.** Offline, docs answer kit.json fields, shelf path, reload, and “how do I register behavior?” with no network.
- **Done when.** Skapie Extensions / local docs alone are enough to author.

### 13.2.2 — packages own feature behavior

- **What this is.** A package can register real behavior against KitApi. If something cannot be done, spike a **host KitApi hook**, not a product kit. Justify every `lib/` growth.
- **How to test.** A proof package registers behavior without adding a starter/product kit; diff shows KitApi/HOST only when a hook was required and documented.
- **Done when.** “New feature” has a package-shaped path, not a `lib/` kit-shaped path.

### 13.2.3 — hard packages fence (MCP-class)

- **What this is.** KitApi may enable MCP-class packages later. Phase 13 does **not** ship an MCP product kit. Demo under examples or a user-authored package is optional, not the gate.
- **How to test.** Fresh starter has no MCP product kit; docs say MCP is a package, not a host feature.
- **Done when.** Scope fence is explicit in docs and in what ships on the starter shelf.

## 13.3 — faults in host status

### 13.3.1 — package load / register / runtime faults

- **What this is.** Use the **existing** top-left host status UI (no permanent new chrome). Show package load/register/runtime faults only when there is an error. App keeps running; user owns bad packages.
- **How to test.** Break a `kit.json` → status shows; fix + reload → clears when healthy.
- **Done when.** Package faults are visible without a dedicated permanent panel.

### 13.3.2 — grant refusals and tool denials

- **What this is.** Same status surface shows grant refusals and tool denials from packages with a clear reason.
- **How to test.** Deny write grant → status shows reason; successful path after allow does not leave a stale blocking error for that success.
- **Done when.** Grant/tool denials are as visible as package load faults.

## 13.4 — author docs wired for in-app future work

### 13.4.1 — Extensions + docs describe the in-app path

- **What this is.** Skapie Extensions and bundled docs tell the starter LLM (and Anthony) that future kits live in `~/.skapie/kits`, how to seed/reload, and how to prove a kit.
- **How to test.** Offline Read of those docs answers “where do I put a new kit?” and “how do I reload?”
- **Done when.** Docs match the running shelf path (not only repo `kits/`).

### 13.4.2 — starter can reach the shelf with tools

- **What this is.** With grants, Read/Write/Edit/Shell (as designed) can create and edit packages under the kits shelf so authoring does not require leaving the app workflow.
- **How to test.** From the starter board, write a file under the kits shelf path the host uses; reload picks it up (or documents the reload action).
- **Done when.** In-app authoring is not blocked by “kits only in the git checkout.”

## 13.5 — phase gate (must all pass)

### 13.5.1 — empty board still works

- **What this is.** Place LLM + Text; trivial completion. Shelf does not force every board to use the full starter.
- **How to test.** Empty-board path still works.

### 13.5.2 — seeded starter still completes one edit

- **What this is.** Lean starter from the user shelf still does a one-line repo edit with grants enforced (Phase 12 gate preserved).
- **How to test.** Read + Write/Edit against a granted repo; disk matches.

### 13.5.3 — starter LLM authors a useful kit (primary gate)

- **What this is.** Using local docs + tools, the starter LLM creates a **useful** kit into `~/.skapie/kits`, reload registers it, place + cable, kit works. **No Flutter rebuild. No host change for that package.**
- **Useful** = ports/props from package + real KitApi behavior (small tool or doc-backed helper is enough). MCP not required.
- **How to test.** Recorded proof: new folder on disk; status clean or explains faults; kit runs on the board; `lib/` untouched for that package.
- **Done when.** This proof is the definition of “future changes can happen inside Skapie.”

### 13.5.4 — exit criteria write-up

- **What this is.** Short note in this file’s Status (or a one-file prove report) listing gate evidence paths/tests.
- **How to test.** A reader can see what was proved without re-deriving it.
- **Done when.** Status at top of this doc flipped to implemented with evidence pointers.

## Out of scope (do not implement in Phase 13)

Marketplace, signing, shipped MCP product kit, swarms, pause/resume product UI, eval corpus, new first-party Dart feature kits. Phase 14+ may deepen composed workflows and polish after this loop is trustworthy.

## Gate for the phase (definition of done)

- [x] `~/.skapie/kits` is default; starter seeded once; user edits preserved
- [x] KitApi + local docs support package authoring offline
- [x] Reload injects packages without Flutter rebuild
- [x] Top-left status shows package + grant/tool faults only when needed
- [x] Starter LLM authors a useful kit into the shelf and uses it with no host change for that package
- [x] Product path for future features is “package on the shelf,” not “new Dart kit in `lib/`”

Implemented. Do not start Phase 14 unless asked.
