# Experiment: POC photo browser & downloader

**Branch:** `poc/photo-browser` (not merged to `main`)
**Status as of:** 2026-09-20

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
| 1. Vendor binaries | **Committed** (`2405dfe`) — scripts written, review pending, binaries not yet produced |
| 2–7 | Not started |

**Task 1 caveat.** `Tools/setup.sh` and `Tools/setup_test.sh` are committed,
but running them has never produced binaries — `Tools/bin/` is empty. As of
2026-09-20 the only missing autotools prerequisite is `pkg-config`
(`autoconf`, `automake`, and GNU `libtool` are installed). `xcodebuild` is
also unusable until `xcode-select` is pointed at Xcode. Both are
local-machine gaps, not code defects.

**Pre-flight ruling on record.** Task 4's brief originally lacked a note —
present in Task 3 — that its new methods must go inside `DeviceBridge`'s
existing class body rather than a separate extension, to reach its `private`
properties. The note has since been folded into
[task-4](task-4-thumbnail-download.md) directly.

## Next step

Review Task 1 (commits `4dbd3f9..2405dfe`), then start Task 2.

## Housekeeping

- Stash entry `stash@{0}` ("WIP on poc/photo-browser: 4dbd3f9") is left over
  from an interrupted step and has never been inspected. Look before dropping.
