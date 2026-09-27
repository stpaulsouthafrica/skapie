# Phase 12 inventory

What exists before the cleanup, and what Phase 12 does with it. Short list, not a redesign.

## Packages

| Package | Tag | Where |
| --- | --- | --- |
| `board.text`, `board.box`, `board.button` | keep (host) | `lib/kit_api/kit_api.dart` |
| `harness.llm` | keep on starter | `kits/harness.llm/` |
| `harness.conversation` | keep on starter | `kits/harness.conversation/` |
| `coding.repository` | keep on starter (now read + write) | `kits/coding.repository/` |
| `tools.read`, `tools.write`, `tools.edit`, `tools.shell` | keep on starter | `kits/tools.*/` |
| `skapie.extensions` | keep on starter | `kits/skapie.extensions/` |
| `demo.note-card` | keep (schema example, off palette) | `kits/demo.note-card/` |
| `tools.propose_patch`, `coding.patch_proposal`, `coding.review_decision`, `coding.apply_patch`, `coding.write_scope` | archive (rebuild notes) | `examples/kits/` |
| `coding.check_spec`, `coding.run_check`, `coding.check_result` | archive (rebuild notes) | `examples/kits/` |
| `harness.run_control` | archive (rebuild notes) | `examples/kits/` |
| `harness.system-prompt`, `harness.tools` | archive (stubs) | `examples/kits/` |
| `tools.list_kits`, `tools.get_kit`, `tools.instantiate_kit`, `tools.add_object`, `tools.remove_object`, `tools.update_frame`, `tools.update_props`, `tools.set_locked`, `tools.save_kit`, `tools.reload_packages`, `tools.register_kit` | archive (rebuild notes) | `examples/kits/` |
| `tools.repo_list_files`, `tools.repo_search_text`, `tools.repo_read_file`, `tools.repo_git_status`, `tools.repo_git_diff` | archive; replaced by `tools.read` | `examples/kits/` |

The matching host runners stay in `lib/tools/` (patch, check, world, repository) as rebuild references. `createAppKitApi` does not register the demoted recipes; tests opt in with `registerDemotedKits` (`lib/tools/demoted/demoted_kits.dart`).

## HOST special-cases

Grouped by kind. Tags: **keep** (irreducible), **move** (package metadata), **drop** (removed with the demoted kit), **config** (single documented place).

### Irreducible host behavior (keep)

- Runner table: `codingToolForName`, `repositoryToolForName`, `proposePatchTool`, `createWorldTools`.
- Effect logic: LLM run, conversation turns, apply/check, run control limits.
- Identity: `isLlmKitObject`, `conversationBody`, `isWorldToolKit`.
- Grant checks: `repositoryGrantReasonForTool`, `llmToolOffer`.
- Editor chrome for text and conversation.

### Look and paint

| Site | Disposition |
| --- | --- |
| `lib/paint/kit_icon.dart` `kitIconForKitId` | kept; icons stay host-side for now (Phase 13 seam) |
| `lib/registry/builtin_types.dart` `_kitRadius` | kept |
| `lib/kit_api/kit_compound.dart` `kitUsesTextPreview` | kept |
| `lib/canvas/scene_object_layer.dart` per-kit chrome | kept; demoted branches unused by default |

### Ports and cables

| Site | Disposition |
| --- | --- |
| `lib/canvas/kit_port_descriptor.dart` `builtinKitPorts` | kept; demoted entries still resolve for examples |
| `worldToolKitPortsFor` | new; drives the four tools' grant inputs from package props |
| `repositoryKitPorts` | read `Out` plus new `Write` output |

### Palette and starter

| Site | Disposition |
| --- | --- |
| `lib/app/command_palette.dart` `defaultCommandActions` | rebuilt to the lean set |
| `lib/app/home_screen.dart` tool loop | filtered by `starterToolKitIds` |
| `lib/app/starter_set.dart` `starterKitIds` | **config** — the one place the default install is defined |
| `lib/app/coding_workflow_starter.dart` | rebuilt to 10 cards and 12 cables |

### Tagged for API notes / rebuild notes

- Propose → Review → Apply, the bounded check, and Run Control: see [rebuild notes](phase_12_rebuild_notes.md).
- Context provenance and compaction stay in host ([Phase 11](phase_11.md)).

## Starter set (product table)

Input (Text) · LLM · Conversation · Output (Text) · Repository (read + write) · Read · Write · Edit · Shell · Skapie Extensions.
