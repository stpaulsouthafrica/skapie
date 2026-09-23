## 11.1 — typed ports and legible board composition

**Goal.** Make manual assembly understandable and extensible without encoding every new kit ID in the canvas.

**Layer.** HOST. Introduce a small built-in port descriptor in core and route existing kit-ID port switches through it. Kit packages do not own hit-testing or cable rules yet; Phase 13 publishes the package contract. Prefer shared port primitives over new `if (kitId == …)` canvas branches.

**Vocabulary.** Use **kit**, **port**, **port row** / **port label**, and **cable**.

**Implementation detail.**

1. Introduce a small built-in port descriptor and move current kit-ID switches behind it. Keep the current scene link format readable while adding stable endpoint IDs only where migration requires them. Phase 13 can later publish this internal contract to user packages; do not design the full external schema now.
   - **What this is.** One shared description of each port (id, direction, value type, multiplicity) so the canvas stops hard-coding kit IDs for every new kit.
   - **How to test.** Open an existing board with LLM, Text, Conversation, Repository, and tool kits. Confirm every port row and cable still appear. Add one more Text → LLM Input cable. Confirm it connects the same way as before. In the diff, new port look-up should go through the descriptor, not a fresh kit-ID branch in canvas code.

2. Validate type compatibility, multiplicity, missing required inputs, stale endpoints, and disconnected grants. Detect cycles only for connections whose value semantics would make them invalid; an unused visual loop need not trigger a generic graph engine. Make validation accessible from the board and Run button. A link can be drawn only when valid or explicitly marked invalid.
   - **What this is.** The board refuses or clearly marks bad cables before Run, including wrong types, too many inputs, dead ends, and grants that are no longer live.
   - **How to test.** Try Text Out → LLM Tools (should refuse or show invalid). Cable a read tool with no Repository (Run or board should say the grant is missing). Delete a kit that still has a cable and confirm the stale end is visible, not silently live. Press Run with LLM Input empty when Input is required and confirm a clear board/Run message. Undo should restore a cut valid cable.

3. Define a connection inspector: source, destination, data or capability role, preview of the value or grant, and last use from current activity when available. Phase 11.2 adds durable past-use evidence. Keep the existing cable-cut affordance and make it keyboard reachable.
   - **What this is.** Selecting a cable shows what it is for (value vs grant), what it carries right now, and whether it was used on the latest run.
   - **How to test.** Select a Text → LLM Input cable and confirm inspector shows source, destination, and a text preview. Select Repository → read-tool cable and confirm it reads as a grant/capability, not ordinary text. After a run that used a tool, confirm “last use” appears only on cables that actually ran. Cut a cable with the existing scissor and with the keyboard path; Undo brings it back.

4. Add one useful overview/detail transition: at small zoom show name and status; at normal zoom show ports and concise content. Defer multi-level semantic zoom, pinning, and elaborate group collapse to Phase 15 unless a specific 11.x screen cannot remain legible without them.
   - **What this is.** Zoomed out, kits read as compact labeled blocks; zoomed in, port rows and short content return.
   - **How to test.** Zoom out until cards shrink: you should see kit name and status, not a wall of port text. Zoom back to normal: Input, Context, Conversation, Tools, Output (and other kits’ ports) are readable again. Pan across a crowded board and confirm overview stays calm.

5. Define a basic keyboard path: find a kit, select a port, list compatible targets, connect, inspect, disconnect, and undo. Mouse motion is an enhancement, not the only path.
   - **What this is.** You can assemble and fix the reader graph without relying on drag alone.
   - **How to test.** Using only the keyboard: focus/find the LLM kit, select Input, choose a compatible Text Out target, connect, open the connection inspector, disconnect, then Undo. Confirm mouse drag still works afterward. Confirm incompatible targets are omitted or explained, not silently connected.

**Stop after.** Items 1–2 are the minimum ship for this slice if time is tight; 3–5 may follow in the same PR only when 1–2 already pass acceptance. Do not start 11.2 here.

**Feel and wow.** Compatible ports respond as a cable approaches; incompatible ones remain still and explain why. A valid drop produces a brief source-to-target arrival, and an invalid drop retreats without pretending to connect. At overview zoom, the board reads like a circuit diagram, not a wall of text; at normal zoom, the source and destination are immediately understandable.

**Acceptance.** A person can build the reader flow with mouse or keyboard, distinguish a read grant from a value cable, find a failed connection, cut it, and restore it via undo. Port metadata is no longer selected by a new kit-ID branch in canvas code. Existing boards still render their links. LLM Conversation remains an output port into Conversation In when that cable is present.
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
