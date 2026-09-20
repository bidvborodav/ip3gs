# Experiment: POC photo browser & downloader

**Branch:** `poc/photo-browser` (not merged to `main`)
**Status as of:** 2026-09-20 (milestone 1: Tasks 1–6 done, Task 7 needs hardware)

## Goal

Prove, end to end, that a modern Mac can connect to an iPhone 3GS, list its
photo library, and download the photos — with a minimal SwiftUI front end.
A proof of concept, not a product.

## Scope

In: connection + trust detection, photo listing, thumbnail grid, "Download
All" to `~/Pictures/ip3gs/`.

Out: photo selection / partial download, delete or write-back to device,
metadata editing, albums, video, folder picker / sandboxing, non-macOS
platforms.

Constraints and the reasoning behind them are in
[`../architecture.md`](../architecture.md#deliberate-non-features).

## Story map (SPIDR / INVEST)

| # | Story | Axis | Brief |
|---|---|---|---|
| 1 | Vendor `libimobiledevice` binaries | **S**pike | [task-1](task-1-vendor-binaries.md) |
| 2 | `DeviceBridge.checkConnection()` | **P**ath | [task-2](task-2-check-connection.md) |
| 3 | `DeviceBridge.listPhotos()` | **I**nterface | [task-3](task-3-list-photos.md) |
| 4 | Thumbnail & download | **D**ata | [task-4](task-4-thumbnail-download.md) |
| 5 | `PhotoLibrary` orchestration + error rules | **R**ules | [task-5](task-5-photo-library.md) |
| 6 | SwiftUI views | **P**ath | [task-6](task-6-swiftui-views.md) |
| 7 | Real-device verification + docs | **R**ules | [task-7](task-7-device-verification.md) |

Task 1 resolves the riskiest unknown (can we get binaries running at all)
before any app code exists. Task 7 closes the gap left by Tasks 2–4, which
parse device output against an assumption rather than an observation.

## Execution state

Run via `superpowers:subagent-driven-development` — one implementer subagent
per task, reviewed before advancing. Ledger:
`.superpowers/sdd/2026-09-12-poc-photo-browser/progress.md`.

| Task | Status |
|---|---|
| 1. Vendor binaries | **Done** — `setup_test.sh` passes: static `ideviceinfo` + `afcclient` 1.4.0, system libraries only |
| 2. `checkConnection()` | **Done, contract corrected** — trust codes parsed from real `ideviceinfo` message format |
| 3. `listPhotos()` | **Done, contract corrected** — `afcclient` driven via stdin, prompts/ANSI stripped |
| 4. Thumbnail & download | **Done, contract corrected** — `get` to a local file; `ProcessRunning` returns `Data` |
| 5. `PhotoLibrary` | **Done** as briefed |
| 6. SwiftUI views | **Done** as briefed — builds; never launched against a device |
| 7. Real-device verification | **Not started** — needs an iPhone 3GS |

**Briefs 2–4 are stale.** Their code blocks assume `afcclient ls <path>`,
`afcclient get <path> -` and an `error code -18` string; all three were
falsified from the 1.4.0 source. The implementation follows
[`../domain.md`](../domain.md#tool-interfaces-verified-from-source), not the
briefs. Plan and deviations: [`PLAN.md`](PLAN.md).

**Verification state.** `xcodebuild build` and `test` succeed (23 tests). All
of them use fakes shaped after the tool source; none has touched a device.
Real binaries were only exercised with no phone attached (`No device found`
paths, exit codes 255 / 1 / 2).

## Next step

**Task 7**, which needs the phone: plug in an iPhone 3GS, run the probes in
[`../research.md`](../research.md#how-to-settle-them), and replace the
source-derived fixtures with real captures. Before that, the app cannot find
its binaries unless launched from the repo root (`binDir` defaults to the
relative `Tools/bin`) — bundle them or pass an absolute path.

## Housekeeping

- Stash entry `stash@{0}` ("WIP on poc/photo-browser: 4dbd3f9") is left over
  from an interrupted step. Inspected 2026-09-20: it only edits the root
  `CLAUDE.md` (adds a house rule: commit **without** Co-Authored-By or session
  links). Not applied, not dropped.
