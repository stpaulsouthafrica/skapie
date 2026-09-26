# Phase 11.5 local task corpus

This is a small outcome evaluation for the human-stepped board in [Phase 11.5](phase_11.md). Each trial starts from a fresh, committed Git repository outside the Skapie checkout. The runner creates no Skapie kit, model loop, or permission grant. It does not choose tool calls for the model. The final answer and files on disk decide the automated score; the two denied-effect tasks also need a person to confirm the refusal shown in the app. This follows [Anthropic's outcome-oriented eval guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents).

## Run one trial

From the Skapie repository root:

```sh
dart tool/phase11_corpus.dart list
dart tool/phase11_corpus.dart prepare locate_symbol /tmp/skapie-11-5-locate
```

The trial folder contains `repo/` (the disposable Git repository), `task.json` (prompt and expected outcome), and `answer.txt` (initially empty). Use a **new blank Skapie board for each trial**, add the coding workflow starter, and select `repo/` in Repository. For edit/check trials, separately select the same folder in Write Scope. The app's folder picker grants access; the path in `task.json` does not.

Paste the prompt from `task.json` into Task Text. Start each LLM turn yourself. Copy the final answer into `answer.txt`. The board's scene path is shown at the top of the app; use its **Copy path** control for the grade command when a trial needs board evidence:

```sh
dart tool/phase11_corpus.dart grade locate_symbol /tmp/skapie-11-5-locate
dart tool/phase11_corpus.dart grade stale_patch /tmp/skapie-11-5-stale '/absolute/path/to/scene.json'
```

The grader reads `scene.json` and its sibling `.runs.json` and `.patch-effects.json` when a scene path is supplied. It prints each PASS/FAIL and exits nonzero if an automated check fails. A `HUMAN` line is an observation that persisted files cannot prove; record it in the [first-use notes](phase_11_5_first_use.md). The grader never changes the repository. Use a **new trial folder** for each repeat so the baseline remains comparable.

## Six tasks and pass conditions

| Task ID | Request | Outcome that counts |
| --- | --- | --- |
| `locate_symbol` | Find `increment`. | Answer gives `lib/counter.dart:1`; Git tree unchanged. |
| `explain_behavior` | Explain `increment(3)` with citation. | Answer says `5`, cites `lib/counter.dart:1`; Git tree unchanged. |
| `edit_one_function` | Fix `increment` and keep `decrement`. | Behavior probe passes; only `lib/counter.dart` changed; final answer names the change. |
| `failing_check_revision` | Apply a first patch with trailing whitespace, run Check, manually start a revision, then check again. | Final behavior and `git diff --check` pass. Board ledger has a nonzero Check, a later agent Run, then an exit-0 Check. Person confirms the revision was manually started. |
| `stale_patch` | Accept a patch, change the file externally, attempt Apply. | The external edit survives; board has an accepted proposal; no applied effect; answer explains the conflict. Person confirms Apply displayed refusal. |
| `permission_loss` | Accept a patch, remove or deny Write Scope, attempt Apply. | Source and Git tree stay unchanged; board has an accepted proposal; no applied effect; answer explains the unavailable write grant. Person confirms Apply displayed refusal. |

For `stale_patch`, after proposal and Accept but **before** Apply, run:

```sh
dart tool/phase11_corpus.dart mutate-stale /tmp/skapie-11-5-stale
```

This intentionally changes only the trial's `lib/counter.dart` to a known external version. It refuses to overwrite a file that has already changed.

For `failing_check_revision`, select the trusted **Git diff --check** preset. The first applied diff must add trailing whitespace to a changed line so Check can fail. Inspect Check Result, then deliberately start the revision LLM turn; if useful, cable Check Result to LLM Context. Apply the new reviewed proposal and run Check again. The grader checks the ledger order and final state, not the names or order of read tools. For `stale_patch` and `permission_loss`, an absent applied-effect record is necessary but cannot prove that someone clicked Apply, so the visible refusal remains a required human observation.

## Interpreting results

These are six capability trials, not a claim about model reliability. A model may fail a prompt; keep the failed result rather than repairing the grader to match one tool sequence. Repeat a case in a new trial directory to measure variance. The automated test suite validates corpus setup and grading with controlled outcomes; it does not spend tokens running a live model. The app's existing patch and check tests separately exercise its effect gates. Later Phase 12 evaluations can reuse these cases while adding multi-turn orchestration and repeat trials.
