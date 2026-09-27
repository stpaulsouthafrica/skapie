# Phase 12 — lean host, starter agent, extensibility seam

Status: **active**. Replaces the archived Phase 12–15 plan in [docs/archive/](archive/README.md).

**North star.** Small host. Packages on disk. User-creatable kits. No new first-party kits “because the phase needed a feature.”

## Agent handoff (read this first)

Give the agent **one** slice ID only (e.g. `12.1.1`). Do not assign 12.2 until 12.1’s gate passes.

**Every turn the agent must lead with:**

- Layer: `KIT PACKAGE` (`kits/<id>/`) | `HOST` (`lib/`) | `GRANT` | `BOARD`
- Kit id (if any)
- One-sentence Change
- Stop after this layer
- Acceptance: diffs show `kits/` vs `lib/`; no kitId special-case look/ports in canvas; justify any HOST touch

**Paste prompt:**

```
Read docs/phase_12.md. Implement ONLY slice <ID>.

Layer vocabulary: KIT PACKAGE | HOST | GRANT | BOARD.
Product: lean host + starter coding agent. Do not invent new first-party feature kits.
Demoted kits go to examples/ or kits archive — off default palette and starter.
Write/Edit are direct tools behind a visible repo write grant (no Review kit on starter).
Shell = repo-root only. Skapie Extensions = bundled local docs only (no curl).
Keep context assembly in host/LLM inspector.

Lead every turn with Layer, kit id, Change, stop-after-this-layer.
Prove with the slice’s How to test. Stay on main. Sheep emoji when done with your rules.
```

**Status:** all Phase 12 slices are implemented. Next opens at Phase 13 (deepen the author API and docs). Evidence: [inventory](phase_12_inventory.md), [rebuild notes](phase_12_rebuild_notes.md), `kits/` for the lean shelf, `examples/kits/` for demoted packages, and the proof tests under `test/app/phase_12_proof_test.dart` and `test/tools/coding_tools_test.dart`.

**Already done:** `12.0.1`, `12.0.2`, `12.0.3`, `12.1.1`–`12.1.3`, `12.2.1`–`12.2.3`, `12.3.1`–`12.3.4`, `12.4.1`–`12.4.3`, `12.5.1`–`12.5.3`.

## Product outcome

Default app = one working coding agent:

| Piece | Role |
| --- | --- |
| Task / input | User request |
| LLM | Model turns |
| Conversation | Thread |
| Output | Model output |
| Repository | Visible read + write grant surface |
| Read / Write / Edit / Shell | Four tools (host runners) |
| Skapie Extensions | Pointers to bundled local kit-author + Kit API docs |

Anything else (compaction, checks, review gates, run evidence, MCP, …) is a **user-authored package** later, not a Phase 12 ship kit.

## Locked decisions

| Topic | Decision |
| --- | --- |
| HOST (`lib/`) | Scene, KitApi, registry, port/cable chrome, grants, runners, traditional tool loop, context assembly |
| KIT PACKAGE | `kits/<id>/` look, port rows, props, capability refs; reload without Flutter rebuild for package-only changes |
| RUNNER | Host-registered only; packages request, host installs |
| GRANT | Read ≠ write; Shell cannot leave granted repo root |
| Write/Edit | Direct tools + visible write grant; no Propose/Review/Apply on starter |
| Shell | Name is Shell (not Bash); cwd/reach = repo grant; no docs fetch |
| Extensions | Local docs only |
| Demoted kits | Move to `examples/` or archive on disk; off palette + starter; keep as rebuild references |
| New kits in Dart | Forbidden for product features; expand HOST only after an explicit spike |

## Lessons (do not re-ship as default kits)

Fold into author docs / optional examples: Propose→Review→Apply, bounded checks, Run Control / pause / resume. Keep context provenance in host. Public kit contract deepens in Phase 13.

## 12.0 — freeze the cut

**Goal.** One active roadmap story.

### 12.0.1 — archive old Phase 12–15 docs — **done**

Old docs live under `docs/archive/` with README pointing here.

### 12.0.2 — rewrite roadmap pointers — **done**

`docs/README.md`, `phase_11_roadmap.md`, Phase 11 handoff / 11.5 lines point at this Phase 12.

### 12.0.3 — Layer vocabulary on every agent prompt — done

Bake the Layer / Change / stop-after-this-layer rules into the Phase 12 handoff habit (and AGENTS.md if needed).

- **What this is.** Same vocabulary as Phase 11, required on cleanup work.
- **How to test.** A sample implement prompt for 12.1.1 includes those fields.
- **Status.** Open (this doc’s Agent handoff section is the template; confirm AGENTS.md still leads with Layer).

## 12.1 — inventory and extract

**Goal.** Know what exists before hiding it.

### 12.1.1 — list packages and HOST special-cases — done

List every `kits/*/kit.json` and every HOST special-case (kitId look/ports, palette, starter placement).

- **What this is.** Checklist, not a redesign.
- **How to test.** Checklist covers all packages and names known canvas special-cases.
- **Deliverable.** `docs/phase_12_inventory.md` (or equivalent short list in-repo).

### 12.1.2 — tag keep / archive / docs / delete — done

Tag each: **keep on starter** | **archive/examples** | **fold into API notes** | **delete** (rare).

- **How to test.** Starter set matches the product table; demoted kits have a path.

### 12.1.3 — rebuild notes for demoted kits — done

Short “how a user would rebuild this” (ports, grants, runners) for Propose/Review/Apply, checks, Run Control at minimum.

- **How to test.** Notes exist and are linkable from kit-author docs later.

## 12.2 — shrink the starter and palette

**Goal.** Default experience is only the lean board.

### 12.2.1 — rebuild the starter board — done

Starter = input, LLM, Conversation, Output, Repository, Read, Write, Edit, Shell, Skapie Extensions.

- **How to test.** Open starter: those cards only; no Check / Run Control / Review required.

### 12.2.2 — demote kits from the default palette — done

Off default palette; packages may stay loadable from examples/archive.

- **How to test.** Palette search does not offer demoted kits by default.

### 12.2.3 — no kitId look/ports special-cases — done

Canvas uses package look/ports; no `if (kitId == …)` paint branches beyond documented irreducible HOST behavior.

- **How to test.** Review/diff proves it.

## 12.3 — four tools, one grant model

**Goal.** Starter tools are Read / Write / Edit / Shell on host runners + repo grants.

### 12.3.1 — Read — done

List/search/read inside repo grant.

- **How to test.** With grant: read + search work. Without: denial recorded.

### 12.3.2 — Write and Edit — done

Direct create/replace/edit behind visible write grant. Host still does path/fingerprint safety. No Accept kit.

- **How to test.** No write grant → refuse. With grant → one-line edit on disk. Outside repo → refuse.

### 12.3.3 — Shell — done

Commands inside granted repo root only.

- **How to test.** Harmless command in repo works; escape outside grant fails.

### 12.3.4 — traditional host tool loop — done

`model.complete` → dispatch → append results → re-call. Embedded streaming later, same dispatcher.

- **How to test.** Tool calls visible; unconnected tool denied with reason.

## 12.4 — kit create / reload and author docs

**Goal.** Packages inject like Pi extensions: no Flutter rebuild for package description.

### 12.4.1 — validate, write, reload, place — done

Prove: validate → write kits root → reload → place → cable.

- **How to test.** Trivial new package appears after reload; ports from metadata.

### 12.4.2 — Skapie Extensions (local docs) — done

Starter kit points at bundled local kit-author + Kit API docs the LLM can Read.

- **How to test.** Paths resolve locally; “what fields does kit.json need?” answerable offline.

### 12.4.3 — scope fence — done

No marketplace, signing, MCP, or live docs URL in this phase.

- **How to test.** Starter path has no network docs dependency.

## 12.5 — proof gate

### 12.5.1 — empty board — done

Place LLM + Text; trivial completion. No forced starter.

### 12.5.2 — starter completes one edit — done

One-line change via Read + Write/Edit (Shell optional). Disk matches.

### 12.5.3 — author one new package without Flutter rebuild — done

Human or starter LLM authors a trivial package from docs; reload; place; cable; no `lib/` change for that package description.

## Out of scope

Swarms, MCP marketplace, pause/resume product UI, eval corpus, new first-party feature kits. Phase 13 = deepen author API/docs after 12.5.

## Gate for the phase

Default install shows only the starter set. Demoted kits are not required to run. Create/reload a package without app rebuild. No canvas kitId look/ports special-cases. One small coding edit works with grants enforced.
