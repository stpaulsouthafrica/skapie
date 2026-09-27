# Phase 12 rebuild notes

How a user would rebuild a demoted flow. The kit packages live under [`examples/kits/`](../examples/README.md); the host runners stay in `lib/tools/` as references. These notes are the same material a kit author would read.

Point the app at the examples shelf to try them:

```bash
flutter run -d macos \
  --dart-define=SKAPIE_KITS_ROOT=/Users/you/Development/skapie/examples/kits
```

## File edits: Propose → Review → Apply

Old shape: a model proposal, a user review, then a separate apply effect. The lean starter replaces all of it with direct **Write** and **Edit** behind one write grant. Rebuild the old flow only if you need a review gate.

- Kits: `tools.propose_patch`, `coding.patch_proposal`, `coding.review_decision`, `coding.apply_patch`, `coding.write_scope`.
- Ports: `proposalResult → proposalIn`, `proposalOut → reviewIn`, `reviewOut → applyIn`, `writeScopeOut → applyWriteScope`.
- Grant: `coding.write_scope` holds a separately chosen folder. The Repository read bookmark cannot satisfy it.
- Runner: `lib/tools/patch/patch_board.dart` (`proposePatchTool`, `invokeApplyPatch`). It fingerprints the file, records a preimage effect, and writes one file.
- Effect log: `scene.json.patch-effects.json` beside the board.

## Checks

Old shape: a trusted Git preset plus a user-started run. The model never gets a free-form command.

- Kits: `coding.check_spec`, `coding.run_check`, `coding.check_result`.
- Ports: `checkSpecOut → runCheckSpec`, `writeScopeOut → runCheckWrite`, `runCheckResult → checkResultIn`.
- Grant: a live Write Scope; cwd is not isolation.
- Runner: `lib/tools/check/check_board.dart` (`invokeRunCheck`), native `macos/Runner/BoundedCheckRunner.swift`, redaction in `check_redaction.dart`.

## Run Control

Old shape: visible per-run limits and a failed-check feedback rule for one LLM.

- Kit: `harness.run_control` with props `modelTurns`, `toolCalls`, `elapsedSeconds`, `outputChars`, `failedCheckRule`.
- Ports: `runCheckFeedback` in, `runControlOut → runControlIn` on the LLM.
- Runner: `lib/agent/run_control.dart` (`runLimitsFor`), panel in `lib/app/run_control_panel.dart`.

## Kit-author world tools

Old shape: the model changed the scene and kits through `tools.list_kits`, `tools.add_object`, `tools.save_kit`, and friends. The lean host instead gives the model `read`, `write`, `edit`, and `shell` over a granted repository, plus a **Reload kit packages** palette action. Authoring is: write `kits/<id>/kit.json`, reload, place, cable.

- Runners: `lib/tools/world/register.dart` (`createWorldTools`) and `lib/tools/world/*.dart`.

## Repository read tools

Old shape: five separate `tools.repo_*` kits. The lean host uses one **Read** tool that lists, searches, or reads.

- Runner: `lib/tools/repository/repository_tools.dart` and `lib/tools/coding/repository_reader.dart`.
