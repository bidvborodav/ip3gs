# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Hobby project: a local macOS app to browse, download, and manage the photo library on an iPhone 3GS from a modern Mac, since the current sync stack (iTunes/Photos/Image Capture) doesn't support this device anymore.

The repository is currently empty — no code has been written yet.

## Tools & Sources

- `xcodegen` manages the Xcode project (project.yml → .xcodeproj). Do not hand-edit the .xcodeproj; edit project.yml and regenerate.
- `deepwiki` is the research tool of choice for understanding relevant device/protocol behavior (e.g. how iOS ~6-era devices expose photo libraries over USB/AFC) before implementing.


## Atomic Commits
After completing each task, create a git commit immediately. Do not batch multiple tasks into a single commit.
**Rules:**
1. One commit per completed task — commit as soon as the task is done. This is standing authorization, do not wait for per commit approval.
2. Stage only the files changed for that specific task (use `git add <files>`, not `git add .`)
3. Write a concise commit message: `<type>: <what changed>` (e.g., `feat: add user auth endpoint`, `fix: resolve null check in parser`)
4. Valid types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`
5. Do NOT push automatically — commits stay local until the user explicitly requests a push
6. If a task touches multiple concerns, prefer splitting into smaller sequential commits
## Delegating to sub-agents
Model tiers for ANY delegated work — Agent-tool calls and Workflow-script `agent()` calls alike. Set the `model` parameter explicitly on every call; never omit it (omission silently inherits the session model):
- `haiku` — mechanical bulk work: renames, boilerplate, format conversion, log triage
- `sonnet` — default for well-specified implementation with clear acceptance criteria
- `opus` — rare; genuinely tricky work: concurrency, subtle algorithms, adversarial verify/judge panels, gnarly debugging. ALWAYS check with me first — never spawn one unprompted.

When unsure between tiers, pick the cheaper and escalate on failure.

## Dynamic workflows (Workflow tool)
Applies to ALL sessions, any model. Dynamic workflows do not need to be avoided — reach for the Workflow tool when a task has 3+ independent parallelizable subtasks or would benefit from a pipeline/judge panel. Standing rule on opt-in: if ultracode is NOT on for the session (no "ultracode" keyword, toggle, or an orchestration request in my own words), check with me first — propose the workflow in one or two sentences with the rough shape and cost, and wait for my reply; my "yes" is the opt-in. If ultracode IS on, invoke directly.
**Agent models inside workflow scripts:** every `agent()` call MUST set the `model` parameter explicitly, chosen per "Delegating to sub-agents" above — with one tightening: NEVER use `opus` agents in a dynamic workflow, not even with approval. Only `haiku`, `sonnet`, or `opus`. If a Opus review is warranted, it happens AFTER the workflow completes, as a standalone Agent-tool call (ask first, per above) — never as a workflow stage.

## Opus sessions: manage, don't execute
Applies ONLY if your system prompt says you are powered by a Opus (smartass-class) model AND you are the top-level session. Sonnet/Haiku sessions, and spawned subagents of ANY model (including `opus` subagents): skip this section and work directly.
You are the most expensive tier. Your comparative advantage is decomposition, judgment, verification, and integration — spend your tokens there and route execution to cheaper models. These are defaults with criteria, not absolutes.
**Act directly (no subagent) when:**
- Understanding, not writing: questions, explanations, reads/greps. Delegate reading only for bulk surveys whose raw output would pollute your context.
- The change is small (roughly ≤30 lines across 1–2 files), or emerges from an active review loop where you already hold the context.
- Writing a self-contained brief would cost more than the task itself — that is the signal delegation is wrong for this task.
- Git operations: you own all staging and commits per the atomic-commits policy above.

**Delegate via the Agent tool when** implementation spans 3+ files, is mechanical/repetitive, or splits into independent pieces that can run in parallel (fan out only when work partitions cleanly by file with no overlapping writes). Pick the model per "Delegating to sub-agents" above. Delegate to minimize total cost and latency, not to maximize delegation — prefer one subagent with a complete brief over many fragments.
**Briefing standard:** subagents see none of our conversation. Every brief must be self-contained — exact file paths, the specific change, acceptance criteria, and the verification command to run — and must state commit policy: default "do NOT commit; the parent session owns commits." Exception — a subagent that is the sole writer in its worktree and is executing multiple sequential tasks may be granted "commit atomically per task as you go"; never grant commit authority to parallel subagents sharing a worktree.

**Reserve for yourself:** planning, architecture, judgment calls, resolving ambiguity with me, and final acceptance of delegated work. You hold the full conversation context; a context-free `opus` subagent doing these is equal cost with worse judgment.

**Workflow tool:** see "Dynamic workflows (Workflow tool)" above — those rules apply to all sessions, Opus included.

**Verify, then commit:** never accept a subagent's self-report as done. Read the actual diff, run the project's verification gate, and check your acceptance criteria — then stage exactly that task's files and commit per the atomic-commits policy above. If you granted a subagent commit authority, verification shifts to its commit series: review `git log -p` over its range and run the gate before treating the work as accepted.

## Notes for future sessions

- Update this file once real structure exists: build/run commands, how xcodegen is invoked, module layout, and how the app talks to the device.

