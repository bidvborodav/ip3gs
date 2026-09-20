# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Hobby project: a local macOS app to browse, download, and manage the photo library on an iPhone 3GS from a modern Mac, since the current sync stack (iTunes/Photos/Image Capture) doesn't support this device anymore.

**Current state:** POC milestone 2 ("usable POC") implemented (2026-09-20) on branch `poc/milestone-2-usable`, cut from `worktree-poc-milestone-1` (milestone 1, itself cut from `poc/photo-browser`; neither is merged). The window no longer freezes: refresh and download run off the main thread with per-file progress and a Cancel button; each photo is pulled once into a cache (`~/Library/Caches/ip3gs/<udid>/`) and reused by "Download All" (measured: cold refresh 74 s + download 6 s = 80 s for 169 files, down from ~156 s); videos are not thumbnailed; both binaries are bundled into `ip3gs.app/Contents/MacOS` and link only system libraries. Verified on a real 3GS by integration tests and XCUITests, and the window was seen. Still open: a *Download All* click in the real window, and the untrusted path ([`docs/research.md`](docs/research.md)). Next: [`docs/experiments/README.md`](docs/experiments/README.md#next-step).

## Documentation

Root file stays under 150 lines and points; everything else lives in `docs/`. Start at [`docs/README.md`](docs/README.md).

| Document | Read it when |
|---|---|
| [`docs/domain.md`](docs/domain.md) | You need to know how the device works — lockdownd, AFC, DCIM, trust/pairing |
| [`docs/architecture.md`](docs/architecture.md) | You're about to change app code — layers, contracts, portability rule |
| [`docs/research.md`](docs/research.md) | **Before writing device-parsing code.** Open questions and unverified assumptions |
| [`docs/best-practices.md`](docs/best-practices.md) | Working agreements, including ones that override Claude Code defaults |
| [`docs/experiments/`](docs/experiments/README.md) | Current POC: scope, story map, per-task briefs, execution status |

Two conventions that bite if ignored: one topic per file, promoted to a directory past ~200–300 lines; and unverified device behavior is marked **[assumed]**, never stated as fact.

## Commands

```bash
./Tools/setup.sh              # one-time: build libimobiledevice into Tools/bin/ (gitignored)
./Tools/setup_test.sh         # verifies setup.sh produced working binaries (no device needed)
xcodegen generate             # REQUIRED after clone and after any project.yml change
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -configuration Debug build
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test \
  -only-testing:ip3gsTests/<TestClassName>      # single test class
# Against a real phone (skipped otherwise): prefix with TEST_RUNNER_IP3GS_DEVICE=1
#   ... test -only-testing:ip3gsTests/DeviceIntegrationTests   # ~80 s, prints DEVICE_REPORT timings
#   ... test -only-testing:ip3gsUITests                        # launches the app, takes over the screen
```

`ip3gs.xcodeproj` is gitignored — it does not exist in a fresh clone. Never hand-edit it; edit `project.yml` and re-run `xcodegen generate`.

### Prerequisites (met as of 2026-09-20)

1. `xcode-select` points at `/Applications/Xcode-beta.app`. The scheme `ip3gs` resolves without a `scheme:` in `project.yml`.
2. Build-time tools: `autoconf`, `automake`, `pkg-config`, and Homebrew `openssl@3` (only its static `.a` files are used; nothing from Homebrew is linked dynamically).
3. `Tools/bin/` is gitignored, so **each worktree/clone must run `./Tools/setup.sh` itself** (~3 min, clones five upstream repos), or copy it from another checkout. The build copies both binaries into the app, so `xcodebuild` (and `xcodegen`'s file references) need `Tools/bin/` populated **before** building.

`setup.sh` builds libplist → libimobiledevice-glue → libtatsu → libusbmuxd → libimobiledevice **statically**; `setup_test.sh` fails if either binary links anything outside system frameworks. Passing this gate means the binaries are portable — but see the two traps in [`docs/domain.md`](docs/domain.md#tool-interfaces-verified-from-source): `afcclient` is an interactive shell, not a subcommand CLI.

`DeviceBridge` resolves the binaries from the app bundle (`Bundle.main.url(forAuxiliaryExecutable:)`), so the app runs from Finder. In `project.yml` the copy is declared **on the source entries** (`buildPhase: copyFiles` + `attributes: [CodeSignOnCopy]`); a target-level `copyFiles:` key is silently ignored by xcodegen 2.44.1.

**"No global/Homebrew installs" governs the shipped tool, not the dev machine.** Installing build-time dependencies locally is fine. What must hold is that the finished app carries its own `ideviceinfo`/`afcclient`, resolves them from its own bundle rather than `$PATH`, and runs on a Mac with no Homebrew. Do **not** satisfy `Tools/bin/` by symlinking Homebrew's libimobiledevice — those link against `/opt/homebrew` dylibs and break portability. Details in [`docs/architecture.md`](docs/architecture.md#binary-resolution-and-portability).

## Architecture in one breath

`SwiftUI views` → `PhotoLibrary` (state + error rules) → `DeviceBridge` (device I/O) → `ProcessRunning` → vendored CLI binaries. Each layer is injectable at the boundary below it, so everything is testable with no phone attached. Full detail in [`docs/architecture.md`](docs/architecture.md).

Three things that will trip you up: `DeviceBridge`'s `binDir`/`runner` are `private`, so new methods go **inside** the class body, never in an extension; there are no modals or alerts anywhere, every state is one status-bar string (plus a progress bar while busy); `PhotoLibrary` is `@MainActor` and runs each blocking bridge call off the main thread, one at a time — never call the bridge from the main actor; and the untrusted-device path is only partly confirmed on hardware (one real `-21`, see `docs/research.md`).

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

- Stash entry `stash@{0}` ("WIP on poc/photo-browser: 4dbd3f9") is left over from an interrupted step and has never been inspected. Look before dropping.
- `poc/photo-browser` is not merged to `main`.
