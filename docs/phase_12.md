# Phase 12 — a reliable single-agent loop

Status: **proposed**. Depends on the [Phase 11 exit gate](phase_11.md#phase-11-exit-gate-and-handoff-to-phase-12). Phase 12 makes a manually assembled coding agent useful for a task that takes many turns, encounters errors, and may outlive one app session. It does not introduce swarms or arbitrary third-party execution.

## Product outcome

The engineer can say, “make this small change,” then watch a bounded agent inspect, propose, ask when needed, run checks, recover from a failed check, and finish with evidence. The engineer can stop or resume it without losing the story. The board remains the editable program for the agent, and every capability comes from a visible kit connection.

Research direction: [Anthropic's agent patterns](https://www.anthropic.com/engineering/building-effective-agents) separate predictable workflows from model-directed loops and recommend adding complexity only when needed. [Context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) treats context as finite and calls for small high-signal inputs. Durable execution systems such as [Temporal](https://docs.temporal.io/) show the value of event history and recovery; Skapie should borrow the principle, not adopt a workflow server by default.

**Agent handoff.** Give an implementation agent this product outcome, the architecture decisions below, one numbered slice, and the Phase 12 exit conditions. Ask for that slice alone, with migration and acceptance evidence. Existing Phase 11 parts are the starting point, not a reason to build a new framework.

## Architecture decisions to settle first

- **Run engine:** one explicit state machine over the Phase 11 event ledger. Suggested states are ready, validating, assembling, model_wait, tool_wait, approval_wait, applying, checking, paused, cancelling, completed, failed, and interrupted. A state transition is committed before its side effect begins and resolved after the observed result.
- **Graph revision:** freeze the board graph and relevant kit configuration for a running turn. A user can edit the live board, but the current turn does not silently gain a new tool or context source. “Apply changes to next turn” is explicit.
- **Effect identity:** every patch application and command invocation receives a durable operation ID. On recovery, inspect the operation record and repository state before deciding whether to retry. Avoid duplicate writes or commands simply because an acknowledgement was lost.
- **Model boundary:** normalize provider request, response, tool-call, usage, cancellation, and error into one small internal shape. Do not erase provider-specific information; attach it as diagnostic metadata.
- **Authority:** the engine can only invoke connected grants that are valid at call time. A paused run does not keep an expired filesystem or command grant alive.
- **Source of truth:** scene for user arrangement, run ledger for facts, repository for code, grant store for authority, and ephemeral UI state for selection. Never use a chat transcript as a substitute for the run ledger.

## 12.0 — bounded turn engine

**Build.** Extend the existing AgentSession/controller path into one small run coordinator with explicit state transitions; do not replace the provider clients or scene system. Define limits for model turns, tool calls, elapsed time, and output volume. Add cost/token budgets only when the chosen provider supplies reliable usage data. Expose limits as board or run settings with visible defaults. Validate the graph and grants before a model request. Record why an unavailable connected tool was excluded.

If a provider already streams, map chunks to the existing event vocabulary; do not make streaming a prerequisite for this slice. A tool call is complete only after its result is recorded. Model text is a draft until the turn or run reaches a terminal state. Normalize provider errors into actionable categories: authentication, rate limit, timeout, invalid tool schema, context limit, transport, and model refusal.

**First-principles composition.** A Run Control kit supplies start, pause, stop, and iteration limit. The LLM kit performs model turns. Tool kits perform effects. A visible Check Result input can permit one more turn under a user-selected rule. The Run Control kit must not secretly attach tools or become a generic workflow interpreter.

**Feel.** The board shows one clear active locus. A small run rail displays turn count, elapsed time, and budget remaining. Model thinking is a quiet waiting state; only actual tool dispatch animates a cable. When a limit is reached, motion stops and the rail explains which limit stopped it.

**Gate.** An offline fake model and a real supported provider follow the same visible state transitions. A model that requests an unconnected tool receives a recorded denial. A timeout, rate limit, or stop request produces an honest terminal or paused state, with no hanging pulse.

## 12.1 — context assembly and provenance

**Build.** Reuse the existing Text, Conversation, Repository, and tool connections as the source of context. Add an inspector preview showing system/context text, task input, selected history, retrieved excerpts, and offered tool definitions before each model request. Each included item has source kit ID, repository path and line range where applicable, ordering, truncation, and reason for inclusion. An excluded item has a reason too. Add a separate Context Filter kit only when a user needs to save or vary those selection rules on the board.

Use just-in-time retrieval from the read kits. Keep a small visible set of high-signal excerpts instead of automatically flooding the model with a repository tree. Make compaction an explicit operation with a source span: it summarizes selected prior events and stores the summary as a derived artifact linked to those events. The full history remains inspectable locally even if the next model request uses the summary.

Define precedence and trust: user task, board-authored instructions, tool outputs, repository text, and imported content retain distinct provenance. Repository text can contain instructions; treat it as task data, not as a grant to alter policy or call a tool. The host enforces grants regardless of what model context says.

**Feel.** Before Run, the Context Assembly view folds into layers. Expanding a layer reveals exactly where its text came from. During compaction, the old segments condense into a labeled summary card while the underlying events remain one click away. Avoid a theatrical “memory transfer” that implies perfect retention.

**Gate.** A user can reconstruct one model request from visible sources and explain why a file excerpt was included. A too-large context is trimmed by a documented rule and shows what was omitted. Compaction never destroys the original run evidence.

## 12.2 — checkpoint, pause, resume, and cancellation

**Build.** Persist a compact checkpoint after stable observed boundaries: model result, tool result, approval decision, patch result, and check result. Record an in-flight event before an effect begins, so a crash leaves it explicitly uncertain. A checkpoint holds run state, graph revision, pending operation IDs, context artifact references, counters, and next permitted transition; it does not duplicate the entire context or scene. Define a schema migration path.

On restart, detect an interrupted run. Reconcile any in-flight operation by inspecting the effect journal and repository state. The user sees Continue, Inspect, or End. Resume starts a new event segment linked to the original run; it does not forge missing results. Cancellation must propagate to model transport and child command processes, then settle at a known state.

Replay is inspection of stored events. Resume is new execution from a checkpoint. Rerun is a new run against current board and repository state. Keep these actions visibly distinct.

**Feel.** Pausing reduces active cable motion to still status markers and a clear “Paused after step N.” Resuming begins at that marker, not at the board origin. An interrupted app launch opens a concise recovery banner anchored to the affected board. Cancelling fades the active path only after the underlying operation confirms stop or is marked uncertain.

**Gate.** A forced process exit at every checkpoint boundary can be recovered without duplicate patch application or a false completion claim. An uncertain command effect is marked uncertain and requires inspection before retry. A stopped run cannot continue silently after app relaunch.

## 12.3 — failure recovery and safe iteration

**Build.** Classify failures as retryable transport, invalid tool input, stale repository state, test failure, permission loss, context overflow, and engine fault. Define a visible policy per class: automatic bounded retry, model self-correction with tool error, human decision, or terminal failure. Backoff and retry count belong in run data. Never retry an effectful operation solely because a network or process acknowledgement was lost.

For failed checks, create a Result artifact that the next model turn may consume through a visible connection. Show the exact diagnostic excerpt and full output link. The model may create a revised patch proposal; it does not overwrite the previous proposal or its review record. A stale patch returns to review rather than trying to force apply.

**Feel.** A failed tool emits a short stop at the kit and a readable error label. A retry is a second event on the same route, visually counted; it is never a smooth continuation that hides the first failure. The iteration loop appears as discrete passes, so the engineer can compare attempt one and two.

**Gate.** The agent can recover from one deliberately failing check, show both proposals and both check results, and finish with an explanation of what changed. Permission loss halts the relevant tool without fabricating a result. Retry limits are honored.

## 12.4 — evaluation and diagnostics bench

**Build.** Extend Phase 11.5's small local task corpus into reproducible cases covering code location, explanation, small edit, failing check repair, stale-file conflict, denial, interruption, and context compaction. For each case, store starting repository fixture, user request, allowed grants, expected outcome, and grading code. Run multiple trials for model-dependent outcomes. Distinguish deterministic contract checks from model-quality evaluations and human feel review.

Measure task outcome, correct file changes, check result, unintended changes, unauthorized tool attempts, run cost, latency, and ability to explain provenance. Include a “no model needed” baseline for simple search and diff tasks. Grade final repository state and user-facing evidence, rather than an exact expected sequence of tool calls. [Anthropic's eval guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) describes why multi-turn traces, multiple trials, and outcome-based graders matter.

Add a diagnostic export with event IDs, schema versions, kit IDs, provider surface, failure category, and timing, with sensitive fields redacted. Keep API keys and unrestricted tool output out of the default bundle. A small report can compare two runs by outcome and first divergent event; leave a full side-by-side visual comparison until engineers need it during regular work.

**Feel.** Task results use plain labels and linked evidence. If a comparison is opened, it points to the first meaningful divergence without crowding the main board while someone is coding.

**Gate.** An implementation agent can demonstrate a regression with a saved task, reproduce its starting conditions, and trace the difference to a model, tool, context, or engine change. The benchmark runner never mutates the user's active repository.

## 12.5 — a complete one-agent task

**Build.** Upgrade the Phase 11 starter board to complete a modest coding task over multiple bounded turns. Keep its existing kits, cables, and manual mode; add Run Control and the visible feedback rule. The run engine should support “inspect only,” “propose,” and “apply after review” as visible settings, all routed through the same kits. Do not ship a second privileged starter or hidden auto-agent service.

**Feel.** The app feels calm during long work: active step, next likely step, budget, and stop control remain visible without a wall of text. Opening the timeline explains the journey. Completion lands on a reviewable result with changed files, check status, and unresolved limitations, then the board returns to rest.

**Gate.** A user can start, pause, close the app, reopen, inspect, resume, review, and finish a small coding task. The final answer is supported by actual repository diff and check evidence. A human can tell when the agent is uncertain.

## Scope boundary and handoff

Phase 12 is a **single-agent reliability** phase. The only new general machinery should serve the explicit run state, event ledger, context artifacts, and effect journal. Keep third-party kit execution, MCP imports, parallel agents, and remote work for later phases. The handoff report must state what is durable, what is reconstructed, and what remains ephemeral.

Phase 13 will let users package and extend these compositions without giving a declarative kit unrestricted authority.
