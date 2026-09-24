

## 11.3 — proposed patches, review, and application

**Goal.** Let an agent propose code changes while preserving the engineer's control over repository effects.

**Implementation detail.**

1. Build four distinct parts: a **Propose Patch tool grant** the model may call; a **Patch Proposal artifact** containing its structured result; a **Review Decision kit** controlled by the user; and an **Apply Patch effect kit** that writes only after a valid review decision. The artifact is data, not an executable tool. Connecting these parts does not apply a patch.
   - **What this is.** Four separate board pieces: the model may call Propose; the result is a data artifact; you own Review; Apply is a separate write effect. Wiring them never mutates the repo.
   - **How to test.** Place all four, cable Propose → Proposal → Review → Apply. Confirm connecting cables alone changes no files. Confirm Propose can create a proposal artifact. Confirm Apply stays inert until a valid review decision exists.

   // done

2. Start with a **single-file, single-region text replacement** tool input: repository-relative path, exact existing text, and replacement text. Limit the first path to an existing regular UTF-8 file; preserve its newline style and permissions, and reject binary files and symlink targets. The host requires one unambiguous match, bounds both strings, reads the file, computes its base fingerprint, and derives the display diff. Reject empty or repeated anchors, paths outside scope, and stale content. Never trust a model-supplied base hash or execute raw patch text. Add multi-file edits, new files, rename, delete, binary, and selected-hunk support only after this path is sound.
   - **What this is.** First Propose shape is one existing text file, one exact substring swap. The host finds the match, fingerprints the file, and builds the diff. Multi-file and other edit kinds stay deferred.
   - **How to test.** Propose a real one-region rename in a UTF-8 source file and open the derived diff. Propose empty/repeated anchors, a path outside the repo scope, a binary file, and a symlink target; each must refuse with a clear reason. Confirm newline style and permissions stay unchanged on a later successful Apply. Confirm a model-supplied base hash is ignored.

3. Prove the native write path before designing the full Apply UI. The existing Repository grant is read-only. Introduce a separate, user-selected write scope and visible grant; do not treat the stored path or read bookmark as write authority. Keep an option to export a proposal when write access is unavailable.
   - **What this is.** Read grant ≠ write grant. Apply needs its own visible write scope. If write is missing, you can still export the proposal.
   - **How to test.** With only Repository read access, confirm Apply is blocked and export still works. Grant a write scope and confirm Apply can proceed after Accept. Confirm the stored repo path alone never unlocks write.

4. Preview a file-level diff and allow Accept or Reject. Bind the decision to the exact proposal ID and content fingerprint; editing a proposal invalidates its earlier acceptance. Accept creates a review decision, but the user still invokes Apply explicitly in this phase. A model's call to Propose cannot approve or apply its own proposal. A later bounded policy may change that, visibly. Auto-apply / YOLO is out of scope for this phase and must be a later visible kit on the same machinery.
   - **What this is.** You inspect the diff, Accept or Reject. Accept only records a decision tied to that exact proposal. You still press Apply yourself. The proposing model cannot approve itself.
   - **How to test.** Reject a proposal and confirm the file is untouched. Accept, confirm a review decision exists, and confirm the file is still untouched until you Apply. Edit the proposal after Accept and confirm the old acceptance is invalid. Confirm a Propose tool call cannot create an Accept or trigger Apply.

5. Check path containment, current file fingerprints, and patch applicability immediately before application. Git's [git apply --check](https://git-scm.com/docs/git-apply) can inform the implementation, but the app still validates authority and path scope itself. A stale file produces a reviewable conflict, not an overwrite.
   - **What this is.** Right before write, Skapie re-checks scope, fingerprint, and whether the patch still applies. Stale disk content stops Apply with a conflict, not a silent overwrite.
   - **How to test.** Accept a proposal, change the target file in another editor, then Apply; confirm a reviewable conflict and no overwrite. Apply a clean proposal and confirm write succeeds. Confirm path-outside-scope is refused even if review was Accept.

6. Record the file preimage and resulting diff. A repository **Revert** is a new, hash-checked effect with its own record; scene undo does not undo disk writes. Never claim multi-file atomicity or guaranteed revert until the chosen storage and write mechanism proves it.
   - **What this is.** After Apply, keep the old bytes and the observed diff. Revert is a separate disk effect that restores the preimage only when the hash still matches. Board undo does not roll back files.
   - **How to test.** Apply a change, Undo on the board, confirm the file stays changed. Run Revert while the file still matches the recorded hash; confirm the preimage returns. Edit the file after Apply, then Revert; confirm it explains the conflict and does not clobber. Confirm docs/UI do not claim multi-file atomicity for this phase.

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
