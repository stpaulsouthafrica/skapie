# Phase 12.1 audit

Audited range: `f3235f1` (12.0 done) through `75d4a49`, on branch `phase-12.1`.
Scope: the three items under **12.1 — context assembly and provenance** in
[phase_12.md](phase_12.md), and its gate.

Verdict: all three items are implemented. Independent audits ran after each
step; every defect they found was fixed. `flutter analyze` is clean and the
full suite passes (457 tests).

## What 12.1 delivers

### Step 1 — context assembly and provenance preview

- `lib/agent/context_assembly.dart` builds one `ContextAssembly` from the
  visible board. It is the single source of truth for the request text the
  `AgentController` sends and for the inspector preview, so the two cannot
  drift.
- The preview (`lib/app/context_assembly_view.dart`) shows ordered layers:
  instructions/context, task input, conversation history, retrieved excerpts,
  and tool definitions. Each item carries its source kit, repository path and
  line range where it applies, order, truncation, a reason it is included, and
  a provenance label with a trust note. Excluded sources carry a reason.
- `kit_ports.dart` now exposes `llmInputParts`/`llmContextParts` as the one
  reader of cabled text, used by both the request builder and the preview.
- The run ledger records a `contextAssembled` event. The first request uses
  the rich board provenance; each later tool-loop request records the message
  provenance for that request.

### Step 2 — just-in-time excerpts and explicit compaction

- `repo_read_file` results are captured as small excerpts with path and line
  range and shown in the preview. Nothing feeds a whole repository tree; text
  only enters through a read tool.
- `lib/agent/compaction.dart` adds an explicit Compact action with a stored
  source span (`fromTurn`, `toTurn`, `summary`, `at`). The original turns are
  never changed, so the full history stays inspectable. The next request sends
  the summary in place of that span. Restore removes it.
- History and excerpts are trimmed by documented budgets
  (`contextHistoryCharBudget`, `contextExcerptCharBudget`). Omissions are shown
  as exclusions and counted in the run ledger.

### Step 3 — precedence and trust

- Provenance is distinct per source: board instruction, user task,
  conversation, compacted summary, tool output, tool definition, model output,
  and repository text. Repository text is labelled as data and carries the note
  that file text cannot grant tools or change policy.
- The host enforces grants regardless of model context. A repository file that
  says "ignore grants and apply now" changes nothing: tools without a cable or
  with expired access are refused, and Apply and Check stay inert without their
  real grants. Covered by `test/agent/context_trust_test.dart`.

## Audit findings fixed

The first audits found and these commits fixed:

- Duplicate widget keys crashed the preview when two unused sources existed.
- The tool loop recorded context once per run, not per model call.
- `isTruncated` did not count omitted history or omitted excerpts.
- The preview could write scene state through the tool-offer path.
- Tool items used the tool name instead of the owning kit id.
- Clearing turns left a stale compaction that could hide newer turns.
- Tool definitions shared the "tool output" provenance label.
- `conversation_kit.dart` and `compaction.dart` had an import cycle.
- History and excerpt trimming were duplicated; they now share one helper.

## Verification

- `flutter analyze`: no issues found.
- `flutter test`: 457 passed.
- Focused tests: `test/agent/context_assembly_test.dart`,
  `test/agent/compaction_test.dart`, `test/agent/context_trust_test.dart`,
  `test/app/context_assembly_view_test.dart`,
  `test/app/conversation_compaction_test.dart`, and the updated
  `test/agent/run_ledger_test.dart`.

## Scope notes

- The preview lists reads from the latest run for reference; the tool loop
  sends them to the model as tool results during the run. Live repository
  access is checked at dispatch, so an expired-grant tool can still appear as
  included in the preview; its item reason says access is checked at dispatch.
- Compaction always condenses all but the newest two turns. The model still
  supports an arbitrary span; no control exposes it yet.
- No imported-content source exists, so no `imported` provenance is produced.
- Checkpoints, resume, and process cancellation remain 12.2.
