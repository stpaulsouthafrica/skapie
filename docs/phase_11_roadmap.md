# Skapie product direction (Phase 11 record + active Phase 12)

The board is the workspace. A person can assemble a coding agent or swarm from visible, small kits and can create another board for another world. Every model input, tool grant, call, permission, effect, and result should be understandable from the board and its run evidence. Animation follows real events and can be reduced or hidden.

The detailed implementation handoffs are separate documents:

- [Phase 11 — inspectable coding-agent board](phase_11.md): typed ports, run evidence, reviewed patches, bounded checks, and a manually reproducible starter agent (historical implementation record).
- [Phase 12 — lean host, starter agent, extensibility seam](phase_12.md): **implemented**. Minimal starter (LLM, I/O, conversation, repository, read/write/edit/shell, Extensions docs). Rock-solid host API; user-authored kits instead of shipping more first-party kits.
- [Phase 13 — injectable packages, user kits shelf, authoring loop](phase_13.md): **implemented**. `~/.skapie/kits`, rich KitApi, LLM-authored packages, host status for faults. No optional product kits (MCP etc. stay packages).
- [Archived Phase 12–15](archive/README.md): former reliable-loop / kit-platform / swarm / beta plan. Kept for archaeology and for kit-author lessons. Do not implement against these unless a task says to learn from them.

Phase 14–15 will be rewritten after Phase 13’s gate. Older sketches of Phases 16–20 live in the archived Phase 15 doc.

## Research synthesis

The sequencing below is **our inference** from the cited engineering guidance, applied to Skapie's board-first product:

- Build a reliable single agent before treating multi-agent work as the default. [Anthropic's agent patterns](https://www.anthropic.com/engineering/building-effective-agents) favor the simplest useful composition, and its [multi-agent account](https://www.anthropic.com/engineering/multi-agent-research-system) describes higher cost and fewer parallel opportunities in many coding tasks.
- Make every offered tool and invocation visible. The [MCP tool specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) calls for clear tool exposure, invocation indicators, and a human ability to deny; Skapie can make those native to kits and cables.
- Persist trustworthy evidence without indiscriminately storing sensitive content. [OpenTelemetry's GenAI attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/) flag tool arguments and results as potentially sensitive; [Anthropic's eval guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) treats multi-turn traces and outcomes as central evidence.
- Separate filesystem read, write, and executable authority. Apple's [macOS sandbox documentation](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) defines distinct limits for user-selected files and executable access. A board cable cannot grant what the host does not possess.
- Use motion to clarify state changes and keep it optional. Apple's [motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion) favors purposeful, brief feedback and reduced-motion alternatives.

## Sequence rule

Keep the core small: scene objects through SceneStore.apply(SceneOp), declarative kit recipes, explicit typed connections, a run ledger for facts, and host-owned capability runners. A kit package describes composition and appearance. A native permission or executable runner must come from the host and remain visible. A starter board and a hand-built board must travel the same execution path, including a Conversation kit the user cables when the agent should remember its own turns. That kit is the live thread the next Run sends. The ledger records what was sent. A pulse shows an event, not merely a connection.

Each phase document contains ordered slices, product behavior, visual feel, failure states, and acceptance gates. Finish and accept a slice's gate before assigning its successor. If a gate needs work scheduled later, correct the handoff instead of silently implementing future slices early. An implementation agent should inspect the current checkout before treating any “current baseline” statement as verified.

## Give one slice to an implementation agent

Send the agent the phase's opening product/architecture rules, **one numbered slice**, and that phase's exit gate. Ask it to stop after the slice, follow the task owner's instructions, inspect the code before choosing an abstraction, and report:

- What changed and why, including schema or migration behavior.
- Which behavior was verified by automated checks, which was observed in the release app, and which still needs human feel feedback.
- Any unresolved permission, data-loss, or compatibility issue before the next slice.

Do not paste only a numbered Build list: its scope depends on the surrounding board, grant, and run-evidence contracts. The later-phase sections are direction, not authorization for the agent to implement them early.

For this repository, the owner's current instruction is to work on `main` without creating a branch. Carry that instruction into agent handoffs; do not assume it is stored in an `AGENTS.md` file.
