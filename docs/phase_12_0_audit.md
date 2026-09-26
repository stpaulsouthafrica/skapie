# Phase 12.0 audit

Audited commit: `2a516fc0ed7eb093d93863210315ac569a9411ae`, on `main`.
Scope: Phase 12.0 in `docs/phase_12.md`, including the missing Run Control palette option.

Verdict: the palette omission and all four engine findings in this audit have been fixed. The tests below cover each correction. This document retains the original findings so the reason for each change remains clear.

## Fixed: Run Control could not be placed from the palette

The kit recipe, registration, ports, inspector and controls existed. However, `lib/app/command_palette.dart` omitted the action, and `lib/app/home_screen.dart` omitted its handler. The dynamic palette list only adds `tools.*` kits, so it could not discover `harness.run_control` automatically.

Added **Add Run Control** and routed it through the existing kit placement path. An app-level test opens the palette, searches for Run Control, submits it, and verifies that only the kit's two objects are added, with control and check-feedback ports. Existing kit ordering is preserved.

## Resolved engine findings

### P1: A pending tool can exceed the elapsed limit indefinitely

`lib/agent/agent.dart:287` awaits tool dispatch without a deadline. The elapsed-time and cancellation checks run only after the tool returns. A model request has a timeout, but tool execution does not. A blocked tool therefore keeps the run waiting and can keep its active marker alive after the displayed budget expires. Stop and Pause also wait for that tool to return.

Reproduced with a tool backed by an unresolved future: a 20 ms run was still pending after 60 ms; only completing the tool allowed the elapsed-limit failure to settle.

Resolution: tool dispatch now waits only for the remaining run time. Stop and Pause also settle the wait immediately. When the result has not been observed, the run ledger records **Tool outcome uncertain** with the call ID, and the inspector uses the same label. A late result cannot append a false completion to that run. The underlying effect may still finish; transport/process cancellation remains in 12.2. No automatic retry is performed.

### P2: A successful HTTP response containing a refusal becomes success

`lib/agent/openai_compatible.dart:163` reads `content` and `tool_calls`, but ignores the `refusal` field. A reply containing `content: null` and a refusal becomes an empty `AgentModelReply`. `AgentSession` treats a reply without tool calls as completion. The new error classifier recognizes refusal words in HTTP errors, but this successful-response path never raises one.

Reproduced by passing a refusal message into `openaiReplyFromMessage`: it returned empty content and no calls. The session's completion branch then explains the false success.

Resolution: explicit refusal fields and blocks on the supported chat, Responses, and Messages surfaces now raise one model-refusal error. Both tool runs and plain completions handle it as a failed run rather than publishing a successful empty answer. Ordinary text that happens to discuss refusal is not classified as an explicit provider refusal.

### P2: Tool-call arguments bypass the output budget

`lib/agent/agent.dart:253` counts reply text and line 294 counts tool results. It never counts the model-generated tool arguments before dispatch. For example, a large patch proposal can exceed the configured output volume while returning a small result, without exhausting the budget.

Resolution: the session counts every generated tool argument string against the output budget before dispatching any call from that model reply. Oversized arguments stop the run without executing the tool.

### P2: Recorded tool availability can contradict the actual request

`lib/agent/agent_controller.dart:531` removes tools whose repository access has expired from `attached`. However, lines 539–542 record `offer.names` and `offer.schemaDigest`, calculated before that permission filter. A tool can therefore appear both offered and excluded in the same request evidence, and the digest can describe schemas never sent to the provider.

Resolution: offered names and the schema digest now come from the final permitted tool list. Exclusion reasons remain in the ledger. A regression test removes repository access before the request and checks that the tool appears only in the excluded list.

## What is implemented

- The existing AgentSession/controller path is extended; there is no replacement scene engine.
- Run Control is registered and exposes Start, Pause, Stop, model turns, tool calls, elapsed seconds, output characters, and a failed-check rule in its inspector.
- Run Control targets a cabled LLM and does not attach tools.
- A cabled failed Check Result with the selected rule adds exactly one to the run's model-turn allowance. This is evaluated when the run starts; it is not an automatic check/repair loop.
- Tool-loop tests cover recorded unconnected-tool denial, grant loss at dispatch, tool-result ordering before the next model request, turn/tool limits, model-wait timeout, and withholding draft text on pause.
- Existing fake-model and mocked HTTP-client tests exercise the same state sequence. These are not a fresh live-provider acceptance run.

## Persistence and scope

Kit settings and connections live in the scene. Run events and result bodies use the existing board ledger when a ledger file is configured. Phase/counter changes are recorded there. In-memory activity, cancellation flags and active markers remain ephemeral. Loading the ledger marks incomplete runs interrupted; it does not reconstruct an executable checkpoint.

Pause currently ends that run segment. Start begins a new run; it does not resume the suspended model/tool loop. Durable checkpoint/resume is explicitly 12.2. Updating the starter board is 12.5. Neither omission is counted as a 12.0 defect here.

## Verification

The palette regression test is in `test/app/command_palette_widget_test.dart`. The remaining cases are covered in `test/agent/run_control_test.dart`, `test/agent/model_refusal_test.dart`, and `test/agent/run_ledger_test.dart`.

- `flutter test --reporter expanded`: 441 tests passed.
- `flutter analyze`: no issues found.
- `flutter build macos --release`: succeeded, producing `build/macos/Build/Products/Release/Skapie.app`.
- `git diff --check`: passed.

The running desktop process was not restarted. Relaunch the rebuilt app to use these changes. Placement and refusal handling were verified with tests, not a hands-on desktop or fresh live-provider session.
