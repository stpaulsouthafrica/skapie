# Phase 13 — an extensible kit platform

Status: **proposed**. Depends on a working [Phase 12 single-agent loop](phase_12.md). Phase 13 lets engineers create and share new board arrangements and use host-approved capabilities through one public kit contract. The platform should make the smallest pieces more reusable; it should not introduce a second opaque agent framework.

## Product outcome

A user can define a kit's visible inputs, outputs, configuration, and composition; validate it; place it on a board; and share it with another user. A capability such as repository read, patch apply, or command execution remains a separately installed host runner with an explicit grant. An imported kit cannot silently acquire more authority than its constituent parts.

The [JSON Schema 2020-12 specification](https://json-schema.org/draft/2020-12) gives a mature vocabulary for validating data contracts. The [MCP tool specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) separates tool names, schemas, results, and invocation. Skapie can use those ideas while keeping its own board-native kit model. Unknown declarations should load as visible, inert objects rather than execute arbitrary code.

**Agent handoff.** Give an implementation agent this product outcome, the design rules below, one numbered slice, and the Phase 13 exit conditions. Ask for that slice alone. Treat the Phase 11–12 contracts and current package code as the baseline before adding new schema fields.

## Platform rules

- The **kit package** is a portable description. The **kit instance** is a scene object or compound on one board. The **runner** is trusted executable code registered with the host. The **grant** is a scoped decision by the user or OS. These four identities must remain separate.
- A composite kit can hide its internal layout for convenience, but opening it reveals the constituent public kits and cables. Saved compositions must not get privileged behavior unavailable to hand-built graphs.
- The package schema is versioned independently of scene and run schemas. Package loading validates before any scene mutation. On import, show requested capabilities, data destinations, and migration effects.
- Port metadata from Phase 11 is the only source for connection compatibility. The canvas must not gain a fresh branch for each third-party kit ID.
- Capability checks happen at dispatch, not just when a package is imported or cable is drawn. A model message or untrusted document cannot enlarge the grant.
- Declarative packages remain safe to inspect when unknown or partly incompatible. Inert placeholders preserve layout and explain missing dependencies.

## 13.0 — public kit contract

**Build.** Publish the smallest validated subset of Phase 11's internal port contract: package ID, package version, display metadata, objects or one level of contained kit references, stable ports, configurable fields, and capability references. Define which fields affect runtime behavior and which are presentation only. Use explicit input and output schemas for structured values. Reject ambiguous port IDs, duplicate object IDs, and invalid defaults. A missing host capability may load as an inert, clearly marked dependency; it must never run.

Evolve today's package schema additively if possible. Bump its schema version only if semantics cannot be preserved; document the migration and retain legacy scene links. A loaded package is pinned to a version for a running board. Cross-install import and package-update UX are later slices, not prerequisites for using the new contract.

Use the types proven in Phases 11–12 first. Add a generic structured value only when a concrete kit needs it. Extension types need a declared validator and renderer fallback, not ad hoc dynamic casting.

**Feel and wow.** A placed package shows its real board appearance and ports. Hovering a port explains type, direction, required status, and grant scope in one compact tooltip. Existing connections remain visually stable after an additive package load. A dedicated pre-placement preview follows in 13.4.

**Gate.** Two independently authored packages with compatible port contracts connect without canvas code changes. An incompatible package remains inspectable, names its missing contract, and does not damage an existing board. Legacy packages continue to load.

## 13.1 — save and unfold compositions

**Build.** Let a user select kits and cables and save them as a **one-level** composite kit. Choose which inner ports are exposed as its public surface. Preserve stable references so changing an inner kit does not silently relink to a different target. Offer “open composite” and “detach copy.” Start instance overrides with text, color, and model; add nested composites, resource overrides, and budget overrides only when their semantics are clear.

The existing starter can be saved as a composition. Whole-board export and import belongs to Phase 15. A composition can request that the user select a Repository on first use, but it excludes credentials and native grants. Its execution path matches manually placing the same parts.

**Feel and wow.** Folding a group into a composite gently gathers its cable endpoints onto a labeled boundary; unfolding returns the same internal positions. This is a navigational transition, not a claim that data moved. A starter agent feels like a prepared circuit the user can inspect down to individual pieces.

**Gate.** Save the Phase 12 starter graph, place another instance on an empty board in the same installation, unfold it, replace one read tool, and run. The resulting tool offer matches the visible graph. No private starter-only code path is involved. Cross-install import follows in 13.5.

## 13.2 — capability registry and scoped grants

**Build.** Generalize the host-owned repository and patch/check runners already proven in Phases 11–12. A capability descriptor needs stable ID, input/output schema, effect class (read, propose, write, execute, network), resource scope, and runner source. Add cancellation and approval fields for runners that use them. The registry resolves kit references to installed runners; it does not load arbitrary code from a package.

Build a grant inspector that answers: what can this kit read or change, for which resource, and which runs used it? Support revoke and reselect. Add time-based expiration only when a concrete runner needs it. A write grant must not be inferred from a read grant. A package may request a capability, but only the host can say it is installed and the user or policy can grant it.

Put permissions at the action boundary. Check repository identity and current scope immediately before a tool call; record the grant decision in the run ledger. Use one permission path for direct user invocation and model invocation so there is no weaker agent-only route.

**Feel and wow.** Grant state is visible on the capability cable and in the kit inspector. A revoked grant turns still with a precise label; a future call stops at the grant boundary. The affordance is quiet when everything is healthy and prominent only when action is needed.

**Gate.** Placing a composition never grants access by itself. Removing a grant blocks the next call even if the board was already open. A run shows which grant authorized each effect. Package import later uses this same permission path.

## 13.3 — prove the adapter boundary

**Build.** Implement one small, read-only adapter outside coding to prove that the public kit contract is domain-neutral. A user-selected local JSON array of records with a bounded exact key/value lookup is enough: the source kit declares its schema, requires an explicit file grant, emits the same run events, and can be replaced without canvas changes. Use a small fixture during development; the shipped proof must work with a user-selected file. Do not add a query language or external authentication for this slice.

MCP is a useful **later adapter candidate**, not part of the Phase 13 exit gate. If explored now, keep it to a research spike that maps one discovered read-only tool to Skapie's kit, grant, and event contracts. Do not ship server discovery, authentication, or a tool marketplace as part of this slice. The [MCP tool spec](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) treats annotations as untrusted unless from trusted servers and recommends visible tool input and confirmation for sensitive actions.

When a real external adapter is scheduled in Phase 16, keep its authentication outside scene/package files, validate endpoints and outputs, and follow the [MCP security guidance](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices).

**Feel and wow.** The new source kit appears as a real board object with its ports and grant when placed. Its first invocation follows the same restrained source-to-result route as a repository read. The user recognizes one coherent system across domains.

**Gate.** A user can place the non-coding read-only kit, connect it, invoke it, inspect the result, revoke its grant, and confirm later invocations fail clearly. No new kit-ID switch appears in the canvas.

## 13.4 — kit authoring and developer experience

**Build.** Extend the existing package loader with an in-app validator and board-scale preview for the public contract; do not build a separate CLI in this slice. Validation reports exact field and port paths and missing host capabilities. Supply two maintained examples: a repository reader composition and the non-coding read-only adapter from 13.3.

Document the host-runner interface proven by the built-ins. A public executable-plugin SDK and sandbox are later work; they are not required for users to author declarative kits. A JSON package by itself never loads a DLL, script, Dart expression, or arbitrary shell command.

Document contract compatibility rules and deprecation windows. Keep examples executable and tied to the current schema rather than prose that drifts. Do not introduce broad code generation or a heavyweight plugin framework merely to save a few repeated descriptors.

**Feel and wow.** Authoring gives immediate, local feedback: the package is shown at actual board scale, and invalid ports explain why. “Place on board” carries the same object from preview to world; it does not produce a different hidden implementation.

**Gate.** A third-party author can make a composition with the documented contract, validate and load it locally, and understand any missing runner without reading Skapie's source code. Sharing it with another installation follows in 13.5.

## 13.5 — package lifecycle and portability

**Build.** Support inspect, import, pin, and export for one composition package. Exports include its manifest, contained kits/cables, and dependency list. They exclude credentials, OS bookmarks, local absolute paths, private run payloads, and user approvals. Import previews missing dependencies and required grants before touching the board. Add package update, rollback, and removal flows only when users need to change an installed package.

Give packages stable IDs and versions with content hashes. Validate size, paths, and referenced packages. Reject a conflicting ID/version with different content rather than guessing which one wins. Signing or a curated catalog can build on this in later phases; local packages need neither.

**Feel and wow.** Import is a readable reveal: package identity, visible kits, exposed ports, missing dependencies, and requested authority appear before commit. Cancelling the preview leaves the board unchanged.

**Gate.** Export the starter agent as a composition, import it on a clean installation, select its repository and model, and run it. The import asks for every missing grant and never leaks the originating user's paths or key. Whole-board portability remains Phase 15.

## Phase 13 exit gate and handoff

The platform is ready when a user can compose, package, inspect, and share a coding agent from public parts; one non-coding read-only kit proves the contract is general; and unknown packages remain inert rather than dangerous. The implementation report should cover schema compatibility, migration evidence, denied-grant behavior, authoring usability, and hands-on motion feedback.

Phase 14 will use these same contracts to make agent instances and delegation into ordinary composable kit arrangements.
