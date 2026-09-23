# Phase 11 — the inspectable coding-agent board

Status: **design and implementation plan**. Phase 11.0 exists as a first code slice; it still needs an audit and hands-on acceptance. This document supersedes the short proposal in [phase_11_roadmap.md](phase_11_roadmap.md). Continue with [Phase 12](phase_12.md) only after the Phase 11 exit gate.

## Outcome and product contract

An engineer can build a useful single coding agent by placing and connecting small kits: task text, LLM, conversation, repository, read tools, proposed patch, review decision, apply action, and checks. A starter arrangement must contain exactly those same user-available parts. The **board is the workspace**; another board is another world. Several boards may refer to one repository, and one board may eventually contain several repositories.

The visual graph answers four questions without opening a log file: **what was connected, what was offered to the model, what actually ran, and what changed**. A cable expresses a configured relationship; an event shows actual use. Never animate a configured cable as though data flowed when the corresponding event did not occur.

Retain the current boring core: scene objects and the SceneStore.apply(SceneOp) mutation path for board changes, declarative kit recipes, host-owned runners, and an LLM turn loop. Keep board layout separate from repository contents, run history, credentials, and native folder grants. User packages can arrange kits; they cannot grant themselves filesystem access or executable code.

Research behind this order: [Anthropic recommends simple composable agent patterns](https://www.anthropic.com/engineering/building-effective-agents); [MCP's tool specification calls for showing exposed tools and visual invocation indicators](https://modelcontextprotocol.io/specification/2025-11-25/server/tools). Those are design inputs, not a requirement to adopt either framework.

## Current baseline and immediate audit

The current checkout has BoardCatalog, a Repository kit, five read-only repository tool grants, a macOS folder picker and bookmark, cable activity, and an in-memory last-run inspector list. Current ports are selected by kit IDs in the canvas. The board graph can assemble a repository reader, but there is no proposed-patch/apply/check path, durable run ledger, general port manifest, or complete agent workflow.

The LLM kit already has Input, Context, Conversation, Tools, and Output. Text cabled into Input is the user message. Text cabled into Context joins into one system message. A Conversation kit is a separate part the user places and cables into Conversation. Nothing spawns it. Its turns are that LLM's earlier user and assistant messages, stored on the kit in the scene, and a successful Run appends the new exchange there. The next Run reads the kit because the cable is connected. Hovering a cable shows a scissor; a click cuts the relationship and both ends retract. Today every feeding cable pulses while a run is in flight. That over-claims. A pulse belongs only to a path an event actually used.

Before extending it, the Phase 11.0 implementer should:

- Walk the actual cold-start path: create board; reload; choose repository; connect one read kit; connect to LLM; run; inspect result; switch boards; restart. Record observed behavior, not inferred behavior from build success.
- Check that moving, deleting, and undoing each compound kit updates its links and visible tool offer correctly. Check duplication only if that action already exists. A deleted repository or grant must not leave an invisible capability active.
- Audit the macOS grant boundary: path identity, bookmark restoration, stale bookmark handling, symlink escape, folder replacement, and what a child Git process can access. The current path string in scene data is an identifier, not an authorization token. Apple's [sandbox and security-scoped bookmark guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) is the reference.
- Separate Git machine output from display output. Prefer stable porcelain status, bound output before parsing, disable external diff/text conversion where appropriate, and expose truncation explicitly. Git documents [stable porcelain output](https://git-scm.com/docs/git-status) and [external diff/text conversion switches](https://git-scm.com/docs/git-diff).
- Confirm the current screenshot's cramped LLM output is handled by an inspector or expandable detail surface, rather than growing every board card into a transcript. The Conversation kit holds the thread. The LLM card does not.
- Confirm a pulse happens only for a path the turn actually used. A connected cable that was not called stays still. The current "every feeding cable pulses" behavior is a gap to record, not the target.

This is an audit of the existing slice, not permission to redesign the core.

## Implementation map for the next agents

The following are **current code seams to inspect**, not a command to put every new behavior in these files:

- Board identity and switching: [board_catalog.dart](../lib/scene/board_catalog.dart), [main.dart](../lib/main.dart), and [skapie_app.dart](../lib/app/skapie_app.dart). Preserve the original scene file and one-way load/migration behavior.
- Kit recipes and packages: [kit_api.dart](../lib/kit_api/kit_api.dart), [world tool kit specs](../lib/tools/world/kits.dart), and the packages under [kits](../kits/). Keep disk packages and in-memory fallbacks semantically aligned.
- Graph and cable behavior: [kit_ports.dart](../lib/canvas/kit_ports.dart), [canvas_viewport.dart](../lib/canvas/canvas_viewport.dart), and [cable_layer.dart](../lib/canvas/cable_layer.dart). Use one connection model for drag, inspector, keyboard, persistence, and Run.
- LLM turn and visible activity: [agent.dart](../lib/agent/agent.dart), [agent_controller.dart](../lib/agent/agent_controller.dart), and [inspector_panel.dart](../lib/app/inspector_panel.dart). A durable event store should become their common fact source rather than copying activity into several UI lists.
- Repository boundary: [repository_tools.dart](../lib/tools/repository/repository_tools.dart), [repository_permission.dart](../lib/tools/repository/repository_permission.dart), and the [macOS channel](../macos/Runner/MainFlutterWindow.swift). Keep path parsing, native grant restoration, and tool schemas independently reviewable.

Before editing, each agent should write down: current schema versions; the exact behavior it will migrate; what event proves the behavior happened; how the user inspects it; and what happens if the operation fails halfway. Deliver one vertical slice with its evidence before adding the next effect class.

### How to delegate one slice

When giving one 11.x section to an implementation agent, include **Outcome and product contract**, **Cross-cutting contracts**, the chosen 11.x section, and the **Phase 11 exit gate**. Tell the agent to inspect current code and repository instructions before editing, and to stop at that slice. This preserves the non-negotiable board, permission, and evidence rules even when sections are copied separately. A slice's animation description is a UX acceptance target; it does not authorize new behavior or a separate animation engine.

## Cross-cutting contracts for every 11.x slice

### Board data, run data, and effects

- **Scene document:** user-authored kit instances, positions, connections, collapse choices, names, colors, and board camera. Scene changes use SceneStore.apply(SceneOp).
- **Run ledger:** append-only facts about one execution: event ID, run ID, parent event when applicable, board ID, scene revision or graph snapshot hash, timestamps, relevant kit IDs, event type, outcome, and bounded redacted payload reference. It is not stored inside scene.json and is not part of scene undo. Keep proposal, review, apply, and revert evidence linked even when old read-only runs are eventually removed.
- **Effect journal:** durable records for proposed or completed repository mutations and command invocations, with input fingerprint, authority, result, and reversal information when applicable. Run events reference effect IDs; a decorative cable is never the record of an effect. Keep effect records separate from scene data and subject to an explicit retention rule.
- **Grant record:** OS or host permission bound to an exact resource and capability. It is not copied with a board export and cannot be inferred from a path or package manifest.

An output kit is a scene anchor and view for generated run artifacts; receiving a proposal, check result, or model answer should not automatically add a new scene object or save the full artifact in scene props. If the user pins an artifact to the board, save a small reference through a SceneOp and keep the content in the run/effect store. Preserve existing LLM output behavior during migration until its replacement has been proven.

The Conversation kit is not an output artifact and not a copy of the ledger. It is the memory the next Run will send, for as long as its cable stays connected. Its turns stay on the kit in the scene. The run ledger records that the turn happened and keeps a bounded fingerprint of the messages that were sent. The ledger is not what the next Run reads. Tool results, patches, and check transcripts are not copied into the Conversation kit. Disconnecting or cutting the cable drops that memory from the next request and leaves the kit's text on the board.

Capture the **relevant configured subgraph** at run start: connected kit IDs, port IDs, safe configuration needed for the request, and the offered tool set. Store references or redacted fingerprints for secrets and sensitive prompt or repository content. Do not copy every scene object and layout change into each event. Later cable edits must not rewrite the historical explanation of what the agent saw.

### Connection semantics

Name each port with stable ID, direction, value type, multiplicity, required/optional status, and effect class. Suggested value types are Text, Conversation, RepositoryRead, PatchProposal, ApprovalDecision, CommandSpec, CommandResult, ToolGrant, and ModelOutput. This is a proposed Skapie contract, not an existing external standard.

Distinguish **data** cables (a value supplied to a kit) and **capability** cables (a host runner offered to the model or a resource granted to a tool). Review decisions and Run are explicit actions in Phase 11. Do not build a generic control-flow graph or scheduler in this phase. A cable is not an ambient OS permission; the host validates the graph and current grant at call time.

Keep graph evaluation intentionally small: a user's explicit Run starts a bounded turn. Passive cable changes update configuration and previews; they do not automatically call a model or execute a command. Graph cycles and ambiguous multiple inputs must produce visible validation states before Run.

Multiple inputs already have an order, and later slices keep it: scene-object order, not a spatial sort. Several Text kits on Input join, in that order, into the user message. Several Text kits on Context join into one system message. Several Conversation kits contribute their turns in that same order, each kit in its own turn order. An empty cable adds nothing. Text and Conversation stay different value types. Conversation is the model's own earlier turns, not a string pasted into the system message.

### Privacy and truthfulness

Credentials stay outside board and run files. Raw tool arguments and results may themselves contain secrets; default run views should show bounded, redacted summaries, with deliberate reveal of permitted local detail. Do not claim that a filename denylist proves content safe. OpenTelemetry's [GenAI attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/) explicitly warn that tool arguments and results can be sensitive.

Every loading, approval, failure, retry, and completion state needs text and shape in addition to color or motion. A failed call does not end with a success flash. Reduced motion changes presentation, never the underlying event sequence. Apple's [motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion) favors brief, purposeful feedback; Flutter exposes [disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html) for custom motion to honor.

### Motion grammar and legibility settings

Use a small motion vocabulary across all Phase 11 slices. These are design targets to tune in the actual release build, not timing guarantees:

- **Hover:** immediate cursor change plus a subtle port halo; no repeating animation.
- **Connect:** one short source-to-target arrival after graph validation; the cable then rests.
- **Invoke:** one directional traversal on the actual event, followed by a quiet active state while that operation is in flight. A cable that is merely connected does not pulse. A stored historical event is a static highlight when selected. Connecting a cable, and cutting one with the scissor, are configuration motion. They are not a claim that data flowed.
- **Result:** settle at the receiving kit and show a text state. Pass, failure, denial, truncation, and cancellation each have a distinct shape/label.
- **Review:** pause the route at Review. No cable continues into Apply before an authorized decision exists.
- **Reduce motion:** replace travel with a brief endpoint emphasis or static state; retain the same text and timeline information.

Give users independent controls for cable traces, card content density, run timeline, and animation intensity. Do not make “hide traces” mean “delete evidence.” At overview zoom show what each kit is and whether it is active; at detail zoom show why and with which data. Route inspection must work with keyboard focus as well as mouse hover.

### Agent handoff convention

Each 11.x slice should be implementable alone after its predecessor. The implementation agent starts by reading this file, the current code, and the relevant foundation documents. It records the exact files touched, migration behavior, acceptance evidence, and remaining limits. It must preserve the current main-board scene and legacy package loading. A design decision that affects a later slice is written back here before code expands around it.

## 11.0 — repository reader and board identity

**Goal.** Establish a manually assembled, read-only agent that can inspect a chosen repository and explain its findings. The existing code is a candidate implementation, not an accepted gate.

**Implementation detail.**

1. Finish the audit above. Use the existing SceneDocument.id as board identity; do not introduce a second board-ID system. Add a user-facing name only if the current file-derived labels prove insufficient. Retain scene.json as the first board and preserve existing saves without making users choose a new world.
2. Show the active board clearly and make New/Switch discoverable outside a memorized palette search. Preserve the ability to put any kit on any board; the Repository kit does not define the board.
3. Give each of the five repository tools structured fields appropriate to its action: reads and searches expose repository-relative paths and line ranges; Git tools expose machine-readable state or diff data; all expose errors and truncation. Search and read operations should report when they skipped unreadable or oversized files.
4. Require a visible Repository connection for each repository tool. Multiple repository sources on one tool should either be rejected or have an explicit selection rule; the preferred rule is exactly one source.
5. Keep read grants read-only. Read tools must not inherit write or command authority. Verify grant loss at execution time as well as when the board opens.

**Feel and wow.** Choosing a folder gives the Repository card a concise name and a short arrival cue. Hovering a valid output changes the cursor and reveals the destination types; dragging a cable previews compatibility before release. A successful connection travels once from source to target and then rests. During an actual read call, a restrained pulse moves from Repository to tool to LLM; the selected tool card gains a live status label. No pulsing occurs merely because the LLM is thinking.

**Acceptance.** A user builds the graph from an empty board, asks for a source location, sees the exact file and line evidence, removes the read tool, and confirms the next request cannot call it. Relaunch preserves board and connections; the OS permission is restored or visibly requests reselection. A switched board shows its own scene without inheriting a hidden agent.

## 11.1 — typed ports and legible board composition

**Goal.** Make manual assembly understandable and extensible without encoding every new kit ID in the canvas.

**Implementation detail.**

1. Introduce a small built-in port descriptor and move current kit-ID switches behind it. Keep the current scene link format readable while adding stable endpoint IDs only where migration requires them. Phase 13 can later publish this internal contract to user packages; do not design the full external schema now.
2. Validate type compatibility, multiplicity, missing required inputs, stale endpoints, and disconnected grants. Detect cycles only for connections whose value semantics would make them invalid; an unused visual loop need not trigger a generic graph engine. Make validation accessible from the board and Run button. A link can be drawn only when valid or explicitly marked invalid.
3. Define a connection inspector: source, destination, data or capability role, preview of the value or grant, and last use from current activity when available. Phase 11.2 adds durable past-use evidence. Keep the existing cable-cut affordance and make it keyboard reachable.
4. Add one useful overview/detail transition: at small zoom show name and status; at normal zoom show ports and concise content. Defer multi-level semantic zoom, pinning, and elaborate group collapse to Phase 15 unless a specific 11.x screen cannot remain legible without them.
5. Define a basic keyboard path: find a kit, select a port, list compatible targets, connect, inspect, disconnect, and undo. Mouse motion is an enhancement, not the only path.

**Feel and wow.** Compatible ports respond as a cable approaches; incompatible ones remain still and explain why. A valid drop produces a brief source-to-target arrival, and an invalid drop retreats without pretending to connect. At overview zoom, the board reads like a circuit diagram, not a wall of text; at normal zoom, the source and destination are immediately understandable.

**Acceptance.** A person can build the reader flow with mouse or keyboard, distinguish a read grant from a value cable, find a failed connection, cut it, and restore it via undo. Port metadata is no longer selected by a new kit-ID branch in canvas code. Existing boards still render their links.

## 11.2 — durable, navigable run evidence

**Goal.** Make legibility a reusable product primitive rather than a last-run inspector widget.

**Implementation detail.**

1. Define small versioned Run and RunEvent records. Start with events the current reader can actually emit: run requested, graph validated, model request started/finished with its offered tool set, tool call started/finished, and run completed/failed/interrupted. Add proposal, approval, and command events only when 11.3 and 11.4 introduce those actions. Use an increasing event sequence and wall time.
2. Bound each saved event payload and each timeline page; warn before stored run history grows unreasonably. Do not silently discard proposal, approval, apply, or revert evidence to meet a size limit. Incomplete runs reopen as interrupted, never as completed. Add retention controls when actual usage shows a need. Store large content separately only when the first bounded record format cannot handle it.
3. Record the exact offered tool set and schema version or digest at model-call time. A connected kit can be filtered out by validation; the record must show why. Capture model/provider, elapsed time, errors, and token usage when supplied, without logging credentials or inventing cost numbers.
4. Render one timeline from the event store. Clicking an event highlights the responsible kit and actual cable on the recorded relevant subgraph. Expand to see bounded input/result detail and collapse to a compact summary. Keep export bundles and elaborate filters for Phase 12 or 15.
5. Reopen and inspect past runs without invoking model calls or tools. A full animated scrubber is optional polish; persistent facts and accurate navigation are the gate. A new run against current state receives a new run ID.

**Feel and wow.** The timeline is a second lens on the board, not a second chat app. Selecting a past event softly lights the exact route taken and leaves all unused cables still. An error stops at the failing kit with a clear label. Users can hide the timeline and traces independently. At low zoom, cards show status and count; opening a kit reveals full evidence.

**Acceptance.** After closing and reopening the app, the user can identify which model, Context text, Conversation turns, repository, grant, and bounded call arguments and outputs produced an answer, subject to deliberate redaction. The ledger's fingerprint of those turns matches what was sent. Editing the Conversation kit afterward changes the next Run and does not rewrite the old one. Approval state becomes part of this same timeline in 11.3. Editing the current graph does not alter the old run. A deliberately interrupted run is visibly interrupted. Sensitive payloads are not placed in scene.json.

## 11.3 — proposed patches, review, and application

**Goal.** Let an agent propose code changes while preserving the engineer's control over repository effects.

**Implementation detail.**

1. Build four distinct parts: a **Propose Patch tool grant** the model may call; a **Patch Proposal artifact** containing its structured result; a **Review Decision kit** controlled by the user; and an **Apply Patch effect kit** that writes only after a valid review decision. The artifact is data, not an executable tool. Connecting these parts does not apply a patch.
2. Start with a **single-file, single-region text replacement** tool input: repository-relative path, exact existing text, and replacement text. Limit the first path to an existing regular UTF-8 file; preserve its newline style and permissions, and reject binary files and symlink targets. The host requires one unambiguous match, bounds both strings, reads the file, computes its base fingerprint, and derives the display diff. Reject empty or repeated anchors, paths outside scope, and stale content. Never trust a model-supplied base hash or execute raw patch text. Add multi-file edits, new files, rename, delete, binary, and selected-hunk support only after this path is sound.
3. Prove the native write path before designing the full Apply UI. The existing Repository grant is read-only. Introduce a separate, user-selected write scope and visible grant; do not treat the stored path or read bookmark as write authority. Keep an option to export a proposal when write access is unavailable.
4. Preview a file-level diff and allow Accept or Reject. Bind the decision to the exact proposal ID and content fingerprint; editing a proposal invalidates its earlier acceptance. Accept creates a review decision, but the user still invokes Apply explicitly in this phase. A model's call to Propose cannot approve or apply its own proposal. A later bounded policy may change that, visibly.
5. Check path containment, current file fingerprints, and patch applicability immediately before application. Git's [git apply --check](https://git-scm.com/docs/git-apply) can inform the implementation, but the app still validates authority and path scope itself. A stale file produces a reviewable conflict, not an overwrite.
6. Record the file preimage and resulting diff. A repository **Revert** is a new, hash-checked effect with its own record; scene undo does not undo disk writes. Never claim multi-file atomicity or guaranteed revert until the chosen storage and write mechanism proves it.

**Feel and wow.** A proposed change arrives as a folded diff artifact attached to its source tool. Opening it reveals the target file and its diff while the board remains in place. Review settles into a recorded decision; a separate Apply action then advances through verify → write → observed diff. Conflict stops at the target file with a clear label. Revert follows a new visible route back to the preserved preimage.

**Acceptance.** A user can request a one-file text change, inspect it, reject it with no file mutation, then accept a later version and explicitly apply it. A stale-base edit is refused. Revert restores the preimage only when its hash check passes; otherwise it explains the conflict. Repository read-only authority alone cannot call Apply.

## 11.4 — bounded commands and checks

**Goal.** Close the coding feedback loop with observable, cancellable execution.

**Implementation detail.**

1. Resolve the macOS execution architecture first. A user-selected read bookmark does not authorize running executables in that folder; Apple's [App Sandbox guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) treats executable access separately. Test the smallest viable signed and scoped execution path for the intended distribution. Document the choice and its limits; do not prescribe a helper process unless the spike shows it is necessary, and never silently disable the app sandbox.
2. Add separate **Check Spec**, **Run Check**, and **Check Result** kits. For the first slice, the user configures one exact executable plus argument list or chooses one trusted predefined check. The model may inspect the result but cannot supply a free-form shell command. Connecting a cable never starts a process.
3. Treat a check as an **effectful execution grant**: build and test commands can write generated files or even source files. Prefer an isolated copy or scoped output directory when feasible; otherwise require explicit repository write scope and record before/after Git state. Execute with exact executable and arguments, minimal environment, a validated working directory, timeout, bounded output, and process-tree cancellation. A contained working directory alone does **not** confine what the process can read, write, or contact; claim isolation only after the chosen OS mechanism proves it. Decide whether network access is permitted and show the decision. Expand to configurable command catalogs only after this path works.
4. Capture command argv, cwd, environment key names, start/end time, exit code, stdout/stderr chunks, truncation, cancellation, and resulting Git state. Redact secrets in display and saved output. Stream chunks into the same run ledger; do not attach an unrelated terminal transcript to the LLM card.
5. Start with the honest result categories **exit 0**, **nonzero exit**, **timeout**, **cancelled**, and **infrastructure error**. A test-specific pass/fail parser is a later adapter; do not infer that every command's exit 0 means the entire task is correct.
6. Offer Repeat Check only as another explicit user action with fresh execution authority. A replayed trace never reruns the process.

**Feel and wow.** While a check runs, its cable carries sparse progress ticks derived from real output chunks. The Result kit shows the latest line and elapsed time; opening it reveals a stable terminal-like transcript. Cancellation changes the visible state immediately, then reports whether the process actually stopped. An exit 0 settles with a brief confirmation of the command result; a nonzero exit opens the first relevant diagnostic.

**Acceptance.** The engineer can tell exactly what ran, where, with which authority, for how long, and how it exited. Timeout and cancellation stop the process tree or clearly report an uncertain stop; neither produces a pass. No command runs because a cable was merely connected. A check result can feed a subsequent **user-started** model turn only if visibly connected.

## 11.5 — assemble the first complete single-agent workflow

**Goal.** Package the above parts into an editable, **human-stepped** coding-agent example without adding a hidden privileged mode. Phase 12 adds the autonomous multi-turn loop.

**Implementation detail.**

1. Provide an optional starter board assembled from public kits: Task Text → LLM Input; Conversation → LLM Conversation; Repository → read tools; each read tool and Propose Patch tool → LLM Tools; Propose Patch tool result → Patch Proposal artifact; Proposal → Review Decision; accepted decision plus write grant → Apply Patch; user-configured Check Spec → Run Check → Check Result. The user places every kit, including Conversation. The starter only arranges the same parts. The user deliberately starts Run, Apply, and Check. Include a compact explanation for each connection.
2. Keep this first complete flow to **one model turn at a time**. If Conversation is cabled, that kit already holds the earlier exchange for the next user-started turn. The user may also feed a failed Check Result into that later turn through a visible input. The check result does not replace the thread. Do not add automatic planning, retries, resume, background loops, or a generic graph scheduler here; those are Phase 12 work.
3. Define a small local task corpus with real outcomes: locate symbol; explain behavior with citation; edit one function; handle a failing check by a manually started revision; refuse stale patch; handle permission loss. Score output and repository state, not a single expected sequence of tool calls. Anthropic's [agent eval guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) supports outcome-oriented grading.
4. Record friction in first-use sessions: time to first correct connection, unexplained invalid links, approval confusion, ability to find evidence, and whether animation clarifies or distracts. Let the user judge motion feel on the actual build.

**Feel and wow.** The starter board appears as a coherent, navigable arrangement of the same parts the user can make. A task produces a comprehensible sequence: source read, proposed change, human review, explicit apply, explicit check, and an evidence summary. The board pauses visibly between decisions. The scene remains calm when idle and informative while active.

**Acceptance.** Starting from an empty board, an engineer can reconstruct the starter agent without special APIs. On a small repository task, they can locate evidence, review a patch, explicitly apply it, run a configured check, inspect a failure, and choose whether to start another turn. They can remove or replace any kit and explain what behavior changes.

## Phase 11 exit gate and handoff to Phase 12

Phase 11 is ready for handoff when the manual and starter flows share one execution path; board, run, grant, and effect data have separate persistence; a tool invocation is visible and attributable; review prevents silent mutation; checks are bounded; and existing boards migrate without losing content. The implementation report should include code paths, schema versions, migration notes, release-build status, automated checks requested by the phase owner, and hands-on macOS acceptance findings. **A successful build alone is not the hands-on result.**

Phase 12 will make this single-agent workflow durable across long tasks, context limits, interruptions, and retries. It should not need to invent another board or kit system.
