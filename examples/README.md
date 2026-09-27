# Examples and rebuild references

This folder is not loaded by the default app. It keeps the kits Phase 12 demoted so a user or a future phase can rebuild them.

## `kits/`

First-party kit packages that are no longer on the default palette or starter:

| Kit | Former role |
| --- | --- |
| `coding.propose_patch`, `coding.patch_proposal`, `coding.review_decision`, `coding.apply_patch`, `coding.write_scope` | Propose → Review → Apply file writes |
| `coding.check_spec`, `coding.run_check`, `coding.check_result` | Bounded checks |
| `harness.run_control` | Run limits and pause/resume policy |
| `harness.system-prompt`, `harness.tools` | Stubs |
| `tools.list_kits`, `tools.get_kit`, `tools.instantiate_kit`, `tools.add_object`, `tools.remove_object`, `tools.update_frame`, `tools.update_props`, `tools.set_locked`, `tools.save_kit`, `tools.reload_packages`, `tools.register_kit` | Kit-author world tools |
| `tools.repo_list_files`, `tools.repo_search_text`, `tools.repo_read_file`, `tools.repo_git_status`, `tools.repo_git_diff` | Old repository read tools |

To try one, point the app at this shelf:

```bash
flutter run -d macos \
  --dart-define=SKAPIE_KITS_ROOT=/Users/you/Development/skapie/examples/kits
```

The matching host runners still live under `lib/tools/` (patch, check, world) as rebuild references, but the default `createAppKitApi` does not register these recipes. In tests, call `registerDemotedKits(api)` from `lib/tools/demoted/demoted_kits.dart` to opt in.

Rebuild steps for each demoted flow: [`docs/phase_12_rebuild_notes.md`](../docs/phase_12_rebuild_notes.md).
