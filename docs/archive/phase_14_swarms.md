# Phase 14 — swarms assembled from small parts

Status: **proposed**. Depends on [Phase 12 durability](phase_12.md) and [Phase 13 kit contracts](phase_13.md). Phase 14 introduces more than one agent on a board, but “swarm” is a composition, not a special runtime that bypasses the board. A single agent remains the best default for many coding tasks.

## Product outcome

An engineer can manually place two LLM/agent instances, give them different context and tool grants, send tasks through visible channels, inspect each worker's route and cost, and combine their findings or patch proposals under review. The same parts can form a sequential review chain, a parallel investigation, or a coordinator-and-workers graph. Nothing about adding a second agent silently shares credentials, repository write authority, or conversation history.

[Anthropic's agent patterns](https://www.anthropic.com/engineering/building-effective-agents) describe routing, parallelization, and orchestrator-worker arrangements as different patterns. Their [multi-agent research write-up](https://www.anthropic.com/engineering/multi-agent-research-system) reports benefits for breadth-first research but also notes higher token use and that many coding tasks have fewer truly parallel parts. Skapie should make delegation available and legible, then measure when it helps.

**Agent handoff.** Give an implementation agent this product outcome, the swarm primitives below, one numbered slice, and the Phase 14 exit conditions. Ask for that slice alone, built on the existing single-agent run and kit contracts. A recipe for several agents should stay a composition of the same parts.

## Swarm primitives

- **Agent Instance kit:** an LLM, run control, context inputs, grants, budget, and result output. It may be a saved Phase 13 composition, fully unfoldable.
- **Task kit:** objective, constraints, expected output contract, source run/agent, priority, and deadline or budget. It is data, not an unrestricted prompt injection route.
- **Delegate tool kit:** asks the host to create a child run against a chosen Agent Instance and task. Its authority is bounded by both the parent's delegation grant and the child's configured grants.
- **Message/Result kit:** typed, attributable handoff between agents with source event IDs and a bounded payload.
- **Join/Review kit (14.2):** waits for selected results, checks their status and schema, and exposes a reviewable synthesis input. It never silently merges repository effects.
- **Shared repository reference:** can be read by multiple agents, while proposed writes are isolated until explicit integration.

These are the smallest useful pieces. A coordinator board is simply an arrangement of them. Keep agent instance identity, run identity, task identity, and board identity distinct.

## 14.0 — independent agents on one board

**Build.** Allow multiple Agent Instance kits, each with its own model choice, turn history, context assembly, grants, limits, and run rail. Give each a stable identity and a small public status. A board-wide overview shows active agents without mixing their internal transcripts. Runs can be started separately; a board is not automatically a single synchronized execution. Start with a fixed small active-run limit; an excess start request is rejected visibly until 14.2 adds a queue.

Each independently started agent uses only its own connected grants. Do not add parent/child authority logic until delegation in 14.1.

**Feel and wow.** Each active agent has a quiet lane with a distinct label rather than a rainbow color. Only actual events move along its cables. Selecting an agent focuses its route and dims unrelated motion without hiding the other agents' statuses. Several idle agents do not make the board shimmer.

**Gate.** Two agents can inspect the same repository with different tool grants; the tool list sent to each model matches that agent's visible connections. Stopping one does not stop the other.

## 14.1 — task delegation and handoff

**Build.** Add explicit handoff contracts for one child at a time: task schema, result schema, parent/child links, timeout, budget, cancellation propagation, and failure policy. A delegation event records which graph revision and grant set the worker received. The parent can await, continue, or cancel; that choice is visible and persisted. If the active-run limit is reached, the task remains undispatched with a clear reason; queued dispatch arrives in 14.2.

Define the authority boundary here: a child has no more authority than its own kit grants and the delegating parent's allowed scope. A parent cannot delegate write or execute merely by describing it in a task. The host validates the effective intersection at dispatch and records it. Transfer only the bounded task and the declared result by default; private history and credentials do not cross. More selective sharing controls follow in 14.3.

Prove one manual arrangement first: **sequential review**, where an implementer result reaches a reviewer agent, then a human review. Parallel investigation and coordinator/worker recipes follow the queue and Join work of 14.2 and the context controls of 14.3.

The parent's intended task is a proposal until dispatch is recorded. A worker's output is a message with provenance, not an instruction that changes the parent's permissions. The result contract may require file/line evidence, patch proposal IDs, or a declared uncertainty.

**Feel and wow.** A task handoff is visible as a small packet moving once from parent to worker when accepted by the engine. The worker's lane wakes only on that event. Returning results travel back with a concise status and evidence count. An undispatched task stays still with its reason; no animation implies the worker is active before it starts.

**Gate.** A sequential reviewer receives exactly one bounded task and returns an attributable result. The engineer can answer who delegated it, what the worker was asked to do, what tools it could call, how much it spent, and what it returned. Missing or malformed results do not count as a successful handoff.

## 14.2 — bounded parallel readers and Join

**Build.** Extend 14.0's fixed active-run limit with a visible first-in-first-out queue. Count model calls and read-tool calls against explicit budgets; add a more complex scheduler only if real tasks show starvation or priority needs. Queue excess work rather than starting unbounded workers. Cancellation and deadline propagation must settle every child run to a known state.

Add Join/Review for two read-only workers inspecting independent questions against the same recorded Git revision and relevant file fingerprints. If the working tree changes underneath them, mark the result stale instead of claiming a frozen snapshot. Join waits for selected typed results, makes missing or failed workers explicit, and exposes a synthesis input. Use Phase 12's task corpus to compare this small parallel read task with one agent before expanding to writer integration.

Keep writes out of this slice. A worker that fails still returns a typed failure result so the coordinator can decide how to proceed.

**Feel and wow.** At overview zoom, queued, running, waiting, and finished tasks occupy stable lanes. Two independent findings return to one deliberate Join. A failed worker's lane stays visibly failed instead of disappearing into a combined answer.

**Gate.** Two readers run under the active limit, Join their attributable results, and compare with one reader on the same task. Queue limits and cancellation behave under load. No worker write or automatic integration occurs.

## 14.3 — communication and context boundaries

**Build.** Let a user choose what crosses an agent boundary: full artifact, summary, selected evidence, or no content. Each message carries provenance and a size limit. Keep private context and credentials within their source agent unless a specific data cable and policy permit transfer. The coordinator sees worker conclusions and linked evidence; it need not ingest entire worker transcripts by default.

Summaries are derived artifacts with source event links, not replacement history. A worker can ask for clarification through a typed Request Information kit. Human replies are recorded as user decisions and are visible to the relevant worker only.

**Feel and wow.** A handoff card can expand from one-line summary to source evidence. Inspecting it highlights the exact source agent and events. Information that was withheld appears as “not shared” rather than an empty value that could be mistaken for no result.

**Gate.** A user can limit one worker to a specific subtree and prevent another from seeing that worker's raw output. The visible message contract matches the actual model context sent at the receiving side.

## 14.4 — reviewed writer integration

**Build.** Let workers produce independent patch proposals against a pinned base. Start with proposals and one explicit integration point; do not let workers write the shared repository directly. Detect overlapping file/hunk changes and changed bases. An Integration kit shows conflicts and asks the engineer to resolve them under the Phase 11 review and apply rules; no last-writer-wins. Keep effect journals separate until a reviewed integration applies to the chosen repository. Count patch proposals and commands against per-worker limits.

Use an isolated working copy only when a concrete task needs execution against a worker's proposed changes. An optional Git worktree adapter can provide separate working trees, as [Git documents](https://git-scm.com/docs/git-worktree), but it is a user-configured isolation mechanism, not a license to create branches in the Skapie implementation repository or to merge automatically. Preserve the owner's main-branch workflow when developing Skapie itself.

**Feel and wow.** A conflict is drawn where proposals meet, with both source paths visible. Integrating accepted work shows a short convergence into one reviewed diff; rejected work remains inspectable in its own lane. Motion ends at Review until the engineer acts.

**Gate.** Two workers proposing edits to the same file cannot silently overwrite one another. The final repository diff can be traced to each originating proposal and review decision. A stale base produces a conflict rather than an implicit retry.

## 14.5 — swarm observability and control

**Build.** Extend the Phase 11 run timeline into a parent/child tree. Give every child run its own events and a board-wide chronology. Show total and per-agent token use when reported, cost only when reliably available and labeled by source, elapsed time, tool calls, and current blockers. A single Stop All control coexists with per-agent stop/pause.

Add focus modes: one agent's internal route, a selected task's entire lineage, and board overview. Collapse inactive lanes; keep their status badges and result links. Search by agent, tool, file, event, and failure category. Provide a readable textual view for accessibility and export.

**Feel and wow.** The board feels like an engineering control room: live routes are sparse and meaningful, the global overview stays calm, and selecting a task reveals its lineage without rearranging every kit. When a worker finishes, its lane settles into a compact artifact. Avoid continuous decorative particles across all agents.

**Gate.** A person can locate the first failing worker, pause it, inspect its exact tool call, and decide whether other independent workers continue. Screen reader and keyboard users get the same status and controls without relying on cable movement.

## 14.6 — prove that swarms help

**Build.** Extend Phase 12's evaluation corpus with genuinely decomposable cases: independent codebase reconnaissance, implementation plus review, and multiple independent hypotheses. Include cases where a single agent is better. Compare outcome quality, unintended edits, available cost data, latency, and human comprehension against the Phase 12 baseline. Do not use “number of agents active” as a success metric.

Provide a starter two-agent arrangement and a starter coordinator arrangement, both editable composites. Document when to choose each and how to collapse to one agent. Human review of board feel and handoff clarity is part of the gate.

**Feel and wow.** The first multi-agent demo should show one clear advantage: two independent findings arriving with evidence, then a deliberate synthesis. The spectacle comes from understanding concurrent work, not from maximum simultaneous motion.

**Gate.** At least one representative task shows a measured benefit that justifies extra cost, and the product also communicates when a single agent is preferable. No swarm path bypasses Phase 11 review or Phase 12 durability.

## Phase 14 exit gate and handoff

Swarms are ready when users can build them from ordinary kits, inspect every delegation and authority boundary, manage concurrency, integrate proposals without silent conflicts, and decide from evidence when parallel work is worthwhile. The handoff to [Phase 15](phase_15.md) focuses on first-use experience, portability, performance, accessibility, and release quality.
