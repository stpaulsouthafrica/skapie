# Phase 12.2 audit

Audited range: `69a863e` (12.1 merged) through `d27922e`, on branch `phase-12.2`.
Scope: the three items under **12.2 — checkpoint, pause, resume, and
cancellation** in [phase_12.md](phase_12.md), and its gate.

Verdict: all three items are implemented. Independent audits ran after each
step; every defect they found was fixed. `flutter analyze` is clean and the
full suite passes (471 tests).

## What 12.2 delivers

### Step 1 — checkpoints and in-flight marks

- `lib/agent/run_checkpoint.dart` writes a small checkpoint after each stable
  boundary: graph validated, model result, tool result, check start and check
  result. A checkpoint holds run state, the graph revision, counters, a
  pending operation id, and the resume link. It never copies the context or the
  scene.
- Checkpoints live beside the board (`<scene>.checkpoints.json`) and are capped.
  The file has its own schema version and a migration entry point.
- In-flight marks are recorded before an effect starts: `toolCallStarted` and
  `checkStarted` in the ledger, and the `prepared` record the patch effect log
  writes before touching a file.
- `closeIncompleteRuns` flags a run whose effect never settled as uncertain, so
  a crash is honest rather than a false completion.

### Step 2 — recovery, reconciliation, and cancellation

- On relaunch, interrupted runs are detected. The recovery banner offers
  **Continue**, **Inspect**, or **End**. Nothing resumes on its own.
- `lib/tools/patch/effect_recovery.dart` reconciles a `prepared` apply or
  revert against the file on disk: applied, not applied, or uncertain. The
  repository is the source of truth, so a lost acknowledgement cannot be
  applied twice. Reconciliation runs at startup and when the inspector opens.
- Continue starts a new run segment linked with `resumedFrom` and a
  `runResumed` event. Counters carry over, so limits still hold. Missing tool
  or check results are never invented.
- Stop settles the run promptly: the model wait is raced against the stop
  signal, and check processes are stopped as a process group. An unobserved
  effect is marked uncertain and needs inspection before any retry.

### Step 3 — replay, resume, and rerun

- The Run evidence section has three distinct actions. **Replay** opens a
  read-only view of stored events and starts no process. **Resume** continues a
  paused or interrupted run from its checkpoint. **Rerun** starts a fresh run
  against the current board and repository.
- Resume is only offered when a checkpoint exists and the effect is not
  uncertain. Rerun needs live input and no active run.

## Audit findings fixed

- The graph revision hashed volatile props; it now hashes only kit identity,
  cables, and grant props, and a resume records `graphChanged`.
- The check in-flight mark was queued, not flushed, before the process started.
- The model wait was not cancellable; Stop now settles it promptly.
- Resumed runs restarted their turn/tool/output budgets; carried counters now
  count against the limits.
- A `prepared` revert was never reconciled; applies and reverts share one path.
- Startup reconciliation ran before the effect log was loaded.
- A late model result after Stop could revive a run as resumable.
- The recovery banner and inspector disagreed about an uncertain run.
- The inspector Resume and Rerun buttons were enabled when they could not act.
- A run abandoned mid-tool by Stop or Pause was treated as settled, so the
  inspector offered Resume. An uncertain tool result now keeps the run
  uncertain, so it needs inspection before any retry.

## Verification

- `flutter analyze`: no issues found.
- `flutter test`: 471 passed.
- Focused tests: `test/agent/run_checkpoint_test.dart`,
  `test/tools/effect_recovery_test.dart`,
  `test/app/run_recovery_banner_test.dart`, `test/app/run_actions_test.dart`,
  and the updated `test/agent/run_ledger_test.dart`.

## Scope notes

- Cancellation settles the run promptly but does not abort the underlying HTTP
  request; the request is bounded by the model timeout. A provider-level abort
  hook is left for later.
- Approval-decision and patch-result boundaries are recorded through the patch
  effect log, not the agent ledger. Proposal and apply events in the ledger
  remain 12.3. A `write_uncertain` apply is settled by reconciliation; the
  apply panel does not yet show it as a separate marker.
- A paused run whose effect was uncertain is not offered in the banner (only
  interrupted runs are); its inspector Resume is disabled, so it must be
  inspected or rerun. Surfacing paused-uncertain runs in the banner is a later
  polish.
- Checks are separate `check` runs in the same ledger. Their reconciliation is
  the uncertainty flag; there is no repository re-read for a check, which is
  honest for `git diff --check`.
