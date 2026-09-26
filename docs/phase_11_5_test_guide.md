# Phase 11.5: one complete human-stepped coding workflow

This is the end-to-end test path for 11.5.1–11.5.4. Use a disposable repository. The starter is a visible arrangement of public kits and typed cables; it does not start work or grant access for you.

## 1. Load and understand the starter (11.5.1)

1. Build locally with `flutter build macos --release`. Quit any older Skapie process and open `build/macos/Build/Products/Release/Skapie.app`.
2. Create a **new blank board**. Press **Space**, search **Add coding workflow starter**, and select it. You should see Task Text, LLM, Conversation, Repository, five read tools, Propose Patch, Patch Proposal, Review Decision, Write Scope, Apply Patch, Check Spec, Run Check, and Check Result. These are the ordinary shelf kits: 17 kits and 21 typed cables.
3. Click several cables. The Inspector's **Why connected** line should explain Task → Input, LLM → Conversation, Repository → tool, tool → LLM Tools, Proposal → Review, accepted Review plus Write Scope → Apply, and Check Spec/Write Scope → Run Check → Result. The optional Result → LLM Context cable starts **unconnected**.
4. On another blank board, place a small subset (Text, LLM, Conversation, Repository, one read tool) yourself and connect the same ports. It should behave the same way as that part of the starter. Connecting alone should not start a model, Apply, or Check.

## 2. Run one turn and choose the effects (11.5.2)

1. Edit **Task Text** to a small request. Choose the disposable folder in **Repository**, select a model, and deliberately press **LLM Run**. With an empty Task Text or missing required inputs, Run should explain the blocker.
2. Inspect Conversation after the turn. If the model invoked `propose_patch`, open **Patch Proposal** for the diff. **Accept** records a decision for that proposal; the file must remain unchanged at this point.
3. Select the **same disposable folder separately** in **Write Scope**. Press **Apply Patch** and confirm the file changed exactly as reviewed. Choose the trusted preset in **Check Spec**, press **Run Check**, and open **Check Result** and its run ledger. No cable or Accept action should have started either effect for you.
4. Start a second LLM turn yourself. Conversation should still contain the earlier exchange. For a failed check, optionally connect **Check Result → LLM Context**, update Task Text, and start the revision turn yourself. The request can receive the short check summary while Conversation still holds the thread. A second turn should not start on its own or while the first is running.

## 3. Try the six outcome tasks (11.5.3)

Use [the local corpus](phase_11_5_corpus.md). From the Skapie checkout run `dart tool/phase11_corpus.dart list`, then `prepare <case> <new-workspace>` for each of `locate_symbol`, `explain_behavior`, `edit_one_function`, `failing_check_revision`, `stale_patch`, and `permission_loss`. Use a fresh board and its trial `repo/` for each case. Copy the final answer into `answer.txt` and run `grade <case> <workspace> [scene.json]`. The grader checks answer, final file behavior, Git state, and persisted board evidence where needed; it does not require one fixed tool-call sequence.

For the stale case, run `mutate-stale <workspace>` **after** proposal and Accept, **before** Apply. The external edit must survive the refused Apply. For permission loss, remove/deny the live Write Scope before manual Apply; the repository must stay unchanged. For the failing-check task, a nonzero check, a later manually started agent turn, and a passing check must appear in that order. The grader prints `HUMAN` where a visible refusal or manual choice cannot be proved from files alone.

## 4. Record the first-use experience (11.5.4)

Use the [first-use sheet](phase_11_5_first_use.md) during a real release-build session. Time the first correct cable from opening the palette. Record any invalid-link confusion, whether Accept was mistaken for Apply, ease of finding the diff and Result ledger, and the participant's own **helps / neutral / distracts** judgment about motion. A build or widget test does not fill in that judgment.

## Expected boundary

The starter does not select Repository or Write Scope folders, configure Check Spec, call a model, Apply, or Check. It does not automatically retry after failure. Phase 11.5 ends with a human choosing each turn and effect; the autonomous loop belongs to Phase 12.
