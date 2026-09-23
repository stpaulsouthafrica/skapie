# Phase 15 — an engineer-ready product

Status: **proposed**. Depends on the inspectable single agent of [Phase 11](phase_11.md), durable work of [Phase 12](phase_12.md), [Phase 13](phase_13.md) kit portability, and optional [Phase 14](phase_14.md) swarms. Phase 15 is the point at which Skapie should feel useful to an engineer who has not followed its development. It is a strong public beta gate; the complete product target remains Phase 20.

## Product outcome

A new user can open Skapie, understand that a board is a world, assemble a small coding agent, choose a repository, inspect tool grants, perform a real task, review the diff, run a check, and understand the result. A more advanced user can unfold a starter, alter its smallest pieces, create a reusable kit, and coordinate agents without losing control. The app stays legible under real repository size and real run length.

The “wow” is **causal clarity**: the user sees exactly why the system acted, can trace an answer to evidence, and can shape the graph with direct manipulation. Motion helps their eye follow events. It never stands in for actual work.

**Agent handoff.** Give an implementation agent this product outcome, one numbered slice, and the Phase 15 exit conditions. Ask for that slice alone and require release-app or hands-on evidence where its gate calls for it. The Phase 16–20 horizon is direction, not scope for a Phase 15 agent.

## 15.0 — first-run journey and teaching by construction

**Build.** Design a first-run path with three choices: Empty board, Assemble a reader, and Open a starter coding-agent board. The guided reader teaches Text → LLM, Repository → read tool, and tool → LLM Tools through actions on the real board. The user can skip, replay, or dismiss instruction. A starter is an ordinary template from Phase 13; opening it does not create a hidden privileged mode.

Use progressive disclosure: the first board emphasizes task, model, repository, and Run; advanced kit configuration remains one click away. Place clear labels on the roles of input, output, and grant ports. Explain why a repository path needs an OS grant and why patch apply/check authority is separate.

Measure first-use comprehension with hands-on sessions: can users assemble a reader, locate the active board, explain a cable, cut it, identify a tool invocation, and find the final diff without coaching? Fix language and flow where they hesitate.

**Feel and wow.** The first connection is tactile but quiet: compatible ports respond, the cable settles, and a short hint says what the LLM will now receive. The tutorial uses the same animations as normal operation. Finishing it leaves a useful board, not a discarded tour.

**Gate.** An engineer unfamiliar with Skapie completes a small read-only task and one reviewed edit. They can rebuild the path manually after seeing the starter. Instruction is dismissible and never blocks ordinary board editing.

## 15.1 — navigating large boards and long runs

**Build.** Extend the run and agent search from Phases 11 and 14 into fast board search across kit names, files cited by runs, run IDs, and tool calls; add jump-to-kit and jump-to-event, fit selection, and a restrained overview/minimap if needed. Keep whole-repository search in the existing read tool rather than building a second index here. Support named groups, notes, and alignment without turning groups into opaque execution units. Extend Phase 11's basic overview/detail behavior with deeper zoom and collapse controls only where large boards need them.

Make the inspector stable: selection changes its content without changing the canvas size. Long output, diffs, and terminal results open in resizable detail surfaces that retain board context. A user can pin two artifacts side by side to compare proposals or check results. Use virtualized lists and lazy payload loading for long timelines.

Define density modes as user settings: quiet, standard, and diagnostic. Quiet retains status and evidence access; diagnostic reveals timings and event IDs. Hiding traces does not remove run history. Board-level defaults can be overridden per kit.

**Feel and wow.** Search dims the world around matching kits and moves the camera purposefully to a selected result. Expanding a run artifact feels anchored to its kit, so the user never loses their place. Zoom transitions preserve spatial orientation. The overview has no perpetual motion.

**Gate.** A user finds a specific failed tool call in a long run and its source kit in a large board without manually scanning. The UI remains responsive with representative large board and ledger fixtures, measured in release/profile builds rather than inferred from debug mode. Flutter's [rendering performance guidance](https://docs.flutter.dev/perf/rendering-performance) recommends profiling real rendering behavior.

## 15.2 — portability and reproducible sharing

**Build.** Make board export/import a first-class workflow. Export includes scene graph, kit package references and versions, optional template assets, and a manifest of required host capabilities. It excludes API keys, OS bookmarks, absolute repository paths, approvals, and private run payloads by default. Offer an explicit evidence export with redaction preview when a user wants to share a run.

Import is a dry-run first: show missing packages, unknown types, migration changes, unresolved ports, and required grants. The user can map a Repository kit to a local folder and select a model before the first Run. Imported boards remain inert until the user runs or grants a capability.

Include a reproducibility card for a coding result: original commit or file fingerprints, package versions, model/provider identifiers, connected tools, review decisions, command/check specification, and resulting diff hash. It is evidence, not a guarantee that rerunning a stochastic model produces the same answer.

**Feel and wow.** An imported board appears as a coherent arrangement with unresolved resources marked in place. Mapping each required resource completes that part of the graph. Export preview makes omissions visible and reassuring, without a flashy “all synced” claim when data stayed local.

**Gate.** Two installations exchange an agent board, rebind their own repository and model, and reach the same available kit/tool configuration without transferring secrets. A recipient can tell which capabilities are missing before running.

## 15.3 — coding ergonomics and evidence

**Build.** Tighten the repository interaction loop already built in Phases 11–12: stable file/path citations, line-range previews, Git status from machine-readable output, reviewable diffs, and check result links. Record any cases where plain file/search tools are insufficient; stronger source navigation and a possible language-service adapter belong to Phase 16. Skapie need not become a full editor to serve this workflow.

Keep the code artifact primary. After an agent claims completion, show changed files, approval record, check status, unresolved errors, and a path to open each file in the user's editor. A model's summary should reference these artifacts, not replace them. Maintain clear ownership of Git operations; a board does not silently commit or publish code.

**Feel and wow.** Clicking a file citation draws attention from the answer to the exact read or patch event, then opens the relevant lines. The visible route conveys why the answer is credible. A completed task settles into a compact “change + checks + evidence” card that can reopen the full run.

**Gate.** On representative repositories, a user can move from a request to a precise file line, patch hunk, and check result without copying paths out of chat. A false claim of success is contradicted by visible failed or missing check evidence.

## 15.4 — accessibility, motion, and performance as product gates

**Build.** Audit and complete the keyboard paths and textual route views introduced in earlier phases: kit placement, port selection, connection, disconnection, review, run, pause, stop, timeline navigation, and grant management. Give ports and cables semantic names and state. Use contrast and shape in addition to accent color for status. Support text scaling and high-contrast themes without destroying graph geometry.

Define a motion system with a limited vocabulary: hover hint, valid/invalid connection, event traversal, waiting, success, failure, pause, and cancellation. Animate only state changes or actual progress. Let users reduce or disable nonessential movement. Flutter's [disableAnimations signal](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html) and Apple's [motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion) should inform the implementation. Reduced motion should replace cable travel with a short highlight or static state label, preserving meaning.

Measure frame time, dropped frames, memory, scene load, board switch, timeline seek, and inspector expansion on realistic macOS hardware. Separate static cable painting from active segments and avoid repainting the whole world for one tool event where possible. Performance targets should be set from a documented baseline and reviewed with actual devices, not invented in prose.

**Feel and wow.** At full motion, active work is easy to follow without visual noise. At reduced motion, the same state changes remain just as understandable. On a large board, direct manipulation stays immediate: cables track the pointer, kits move with it, and stopping a run feels responsive.

**Gate.** Keyboard and screen-reader users can perform the core task. Every status conveyed by motion is also available in text. A hands-on feel review covers hover, drag, cable cut, run, error, pause, and large-board navigation; automated rendering metrics support but do not substitute for that review.

## 15.5 — release, support, and real-world acceptance

**Build.** Define a release checklist: schema migration and rollback, clean install, existing-user upgrade, offline/Fake path, provider connection, repository grants across restart, read/propose/apply/check flow, interrupted-run recovery, kit import, reduced motion, and large-board performance. Test on actual macOS releases and signed distribution builds. A local build or successful launch is one piece of evidence, not a completed user workflow.

Publish concise user docs for board/world, kit/recipe/package/runner/grant, manual agent assembly, permissions, run evidence, and recovery. Publish extension docs from Phase 13 separately from user guidance. Extend Phase 12.4's diagnostic export into a bundle users can inspect before sharing. Support reports should identify board and run IDs without collecting repository contents by default.

Dogfood Skapie on its own repository and several unrelated codebases. Record tasks where the product saved time and tasks where it confused the engineer. Use Phase 12 outcome evals and hands-on sessions to decide which friction to remove before broadening scope.

**Feel and wow.** The release build should feel composed: fast cold open into the last board, no surprise model call, calm idle state, crisp direct manipulation, clear permission prompts, and a final result that feels earned because every step can be inspected.

**Gate.** A new engineer completes the end-to-end task unassisted; an advanced engineer constructs and exports a custom arrangement; support can diagnose a failed run from a user-approved evidence bundle; existing board files survive upgrade.

## Phase 15 exit and the road to Phase 20

At Phase 15, Skapie should be an engineer-ready beta for constructing a single coding agent and an optional small team of agents from visible kits. The remaining phases turn it into a complete, durable, extensible product:

### Phase 16 — broader engineering environments

Support multiple repositories, remote development and explicit environment adapters, stronger source navigation, and portable check execution. Build on Phase 13's non-coding read-only proof with a non-coding effect kit to show the graph can express another domain's workflow. A carefully scoped MCP adapter may join here after its trust and authentication boundary is reviewed. Each source or environment remains a kit and a scoped grant. Preserve the board as the workspace rather than replacing it with a project shell.

### Phase 17 — governed autonomy

Introduce configurable, inspectable policies for bounded automatic application, long-running schedules, external network effects, and organization settings. Policies attach to capabilities and runs; they do not hide an elevated “auto mode.” Add stronger prompt-injection and data-exfiltration evaluations. The [MCP security guidance](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices) is one useful threat-model input.

### Phase 18 — ecosystem and collaboration

Provide an isolated, permission-scoped runner host and documented SDK for user-authored executable capabilities. Prove that a runner cannot gain filesystem, network, or process authority merely from a manifest. Then grow a curated kit and adapter ecosystem with provenance, compatibility, versioning, review, and revocation. Add shared board review and handoff that preserve each agent's trace and authority. Keep local, hand-built declarative kits fully supported without a marketplace.

### Phase 19 — scale and reliability

Harden large boards, many runs, long histories, offline operation, crash recovery, migrations, and cross-platform behavior where supported. Show measured success and cost for single agents and swarms. Do not call a motion or rendering improvement complete until people test its feel in the real app.

### Phase 20 — complete product gate

A user can start with an empty world and assemble a coding agent, a swarm, or another domain-specific agent system entirely from documented small kits; grant only the capabilities desired; understand every model input, tool call, permission, effect, and result; pause, resume, replay for inspection, and recover; review or govern code changes; run checks; create and share their own kits; and carry the board to another installation without leaking secrets. Starter experiences accelerate this path but use the same public parts. Skapie feels alive through truthful, configurable motion and stays legible when motion is reduced or the graph grows.

Completion should be judged by end-to-end engineering tasks, extension-author success, migration/recovery evidence, accessibility and performance evidence, and hands-on user acceptance. The number of kits, animations, agents, or integrations alone is not the product gate.
