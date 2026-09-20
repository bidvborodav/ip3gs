# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Hobby project: a local macOS app to browse, download, and manage the photo library on an iPhone 3GS from a modern Mac, since the current sync stack (iTunes/Photos/Image Capture) doesn't support this device anymore.

Current state: a POC is being built on branch `poc/photo-browser`. The app target is still the xcodegen scaffold (`ContentView` renders a `Text("ip3gs")` placeholder); only the dependency-vendoring scripts under `Tools/` have been implemented so far. See `STATUS.md` for per-task execution state.

## Commands

```bash
./Tools/setup.sh              # one-time: build libimobiledevice into Tools/bin/ (gitignored)
./Tools/setup_test.sh         # verifies setup.sh produced working binaries (no device needed)
xcodegen generate             # REQUIRED after clone and after any project.yml change
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -configuration Debug build
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test \
  -only-testing:ip3gsTests/<TestClassName>      # single test class
```

`ip3gs.xcodeproj` is gitignored (`*.xcodeproj`) — it does not exist in a fresh clone and must be regenerated from `project.yml`. Never hand-edit the `.xcodeproj`; edit `project.yml` and re-run `xcodegen generate`.

### Environment prerequisites (currently unmet on this machine)

Neither the build nor the test command has ever run successfully here. Two blockers, both local-machine setup rather than code defects:

1. `xcodebuild` is unusable — `xcode-select` points at `/Library/Developer/CommandLineTools`. `/Applications/Xcode-beta.app` is installed but not selected. The user must run `sudo xcode-select -s /Applications/Xcode-beta.app` themselves.
2. `./Tools/setup.sh` has not produced binaries — `Tools/bin/` exists but is empty. Of the four autotools prerequisites, `autoconf`, `automake`, and GNU `libtool` (as `glibtoolize`) **are** installed via Homebrew; only **`pkg-config` is missing**. `libimobiledevice` and `usbmuxd` are not installed either. (`STATUS.md` claims all four autotools are missing — that is out of date as of 2026-09-20; verify with `command -v` before trusting it.)

**What "no global/Homebrew installs" actually means** (user clarification, 2026-09-20): the constraint governs the *shipped tool*, not the dev machine. Installing build-time dependencies locally for the POC is fine — the remaining unblock is `brew install pkg-config`. What must hold is that the finished app is **self-sufficient and portable**: it carries its own `ideviceinfo`/`afcclient`, resolves them from its own bundle (or `Tools/bin/` in dev builds) rather than `$PATH`, and runs on a Mac with no Homebrew and no libimobiledevice installed.

Practical consequence: **do not** satisfy `Tools/bin/` by symlinking Homebrew's `libimobiledevice` binaries. Those link against dylibs under `/opt/homebrew` and would break portability the moment the app leaves this machine. `Tools/setup.sh` builds from source precisely so the output can be made self-contained. A brew-installed binary is acceptable only as a throwaway crutch for a local dev loop — never as the thing that ships, and never committed to as the path forward without saying so out loud.

Also note `project.yml` defines no `scheme:`, so `xcodegen generate` writes no shared scheme — whether `-scheme ip3gs` resolves via Xcode's autocreation is unverified. If it fails, add a scheme to `project.yml` rather than creating one by hand in Xcode.

## Architecture

Three layers, each independently testable, deliberately kept thin (this is a POC — correctness and honest failure states over polish):

1. **`DeviceBridge`** (`Sources/ip3gs/DeviceBridge/`) — the only code that touches the device. It shells out via `Process` to the vendored CLI binaries `ideviceinfo` and `afcclient`, located by path relative to the app's resource bundle (or `Tools/bin/` in dev builds) — never via `$PATH` or a system install, and never via C interop. This resolution rule is what makes the shipped app portable; see the prerequisites note above. All process execution goes through an injectable `ProcessRunning` protocol so parsing logic is unit-testable against captured sample output with no physical device.
2. **`PhotoLibrary`** (`Sources/ip3gs/PhotoLibrary.swift`) — `ObservableObject` owning `[PhotoAsset]`, thumbnails, and download state. The sole consumer of `DeviceBridge`, and it consumes it through a `DeviceBridging` protocol so tests inject a fake. This is where the error rules live: not-connected / untrusted / per-file-failure-is-non-fatal.
3. **SwiftUI views** (`Sources/ip3gs/`) — one window: status bar, `LazyVGrid` thumbnail grid, one "Download All" button. Stateless read of `PhotoLibrary`; no new business logic.

Consequences of this shape worth knowing before editing:

- `DeviceBridge`'s `binDir` and `runner` are `private`, so new methods go **inside** the existing `final class DeviceBridge { ... }` body, not in a separate extension — an extension can't reach them and won't compile.
- No modals or alerts anywhere. Every state — including errors — surfaces as plain text in the status bar.
- Download destination is hardcoded to `~/Pictures/ip3gs/`, chosen specifically to avoid folder-picker and sandbox-entitlement work.
- `DeviceBridge`'s `afcclient`/`ideviceinfo` argument and output parsing is written against a *documented assumption*, not observed real-device output. Plan Task 7 exists to close that gap against real hardware; if reality differs, fix the parsing **and** update the test fixtures to match reality.

## Project docs

Specs and plans live under `docs/` (kept out of source dirs per the user's documentation rule):

| Artifact | Path |
|---|---|
| Design spec (scope, constraints, out-of-scope) | `docs/superpowers/specs/2026-09-12-poc-photo-browser-design.md` |
| Implementation plan (7 SPIDR/INVEST tasks) | `docs/superpowers/plans/2026-09-12-poc-photo-browser.md` |
| Execution ledger | `.superpowers/sdd/2026-09-12-poc-photo-browser/progress.md` |
| Live status / next step | `STATUS.md` (untracked) |

The plan explicitly **disables TDD** for this POC: write the implementation, then a single verification test after the fact. Do not run red-green cycles here — this overrides the default `superpowers:test-driven-development` guidance for work on this plan.

## Research

For device/protocol behavior (how iOS ~6-era devices expose photo libraries over USB/AFC), prefer `deepwiki` when it is available in the session; it is not configured as a project-level MCP server, so fall back to web search if the tool isn't present.


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

## Housekeeping

- A stash entry `stash@{0}` ("WIP on poc/photo-browser: 4dbd3f9") is left over from an interrupted step and has never been inspected. Do not assume it's disposable — look before dropping.
- `poc/photo-browser` is not merged to `main`.

