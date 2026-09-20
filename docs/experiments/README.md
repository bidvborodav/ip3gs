# Experiment: POC photo browser & downloader

**Branch:** `poc/photo-browser` (not merged to `main`)
**Status as of:** 2026-09-20 (milestone 1 reached; Task 7 verified on hardware except the untrusted path)

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
| 7. Real-device verification | **Done except the untrusted path** — connection, listing, and all 169 downloads verified on a real 3GS (`DeviceIntegrationTests`); untrusted state needs an unpaired phone; GUI not launched |

**Briefs 2–4 are stale.** Their code blocks assume `afcclient ls <path>`,
`afcclient get <path> -` and an `error code -18` string; all three were
falsified from the 1.4.0 source. The implementation follows
[`../domain.md`](../domain.md#tool-interfaces-verified-from-source), not the
briefs. Plan and deviations: [`PLAN.md`](PLAN.md).

**Verification state.** `xcodebuild build` and `test` succeed. 23 unit tests
use fakes. `DeviceIntegrationTests` (5 tests, opt-in) ran against a real
iPhone 3GS on 2026-09-20: connected + UDID, listing, byte-correct JPEG, clean
failure on a missing file, and a full-library refresh + download-all (169 of
169, 0 failures). Run them with:

```bash
TEST_RUNNER_IP3GS_DEVICE=1 xcodebuild -project ip3gs.xcodeproj -scheme ip3gs \
  -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceIntegrationTests
```

**Not verified:** the SwiftUI window itself was never launched or seen (no way
to drive the GUI from the session), and the untrusted-device path.

## Next step

**Milestone 2 — "usable POC"** (branch `poc/milestone-2-usable`, from milestone 1): the app
launches from Finder and stays responsive with the phone attached. Plan, task list and the
judgement calls to review: [`milestone-2-plan.md`](milestone-2-plan.md). Milestone 3 is the
native sync app's Phase 0 spikes (one `afcclient` session doing many `get`s vs one spawn per file).

The list below is the original gap analysis the plan answers:

1. **Unblock the UI.** `refresh()` and `downloadAll` each block for ~77–79 s on
   169 files (measured). Move them off the main thread and publish results
   incrementally — this is what makes the app usable.
2. Bundle `Tools/bin` into the app: `binDir` defaults to the relative
   `Tools/bin`, so the app only finds its binaries when launched from the repo
   root.
3. Launch the app and eyeball the grid; try the untrusted path on a phone that
   has not paired with this Mac.
4. Decide about `.MOV` (filter, or download deliberately).

## Housekeeping

- Stash entry `stash@{0}` ("WIP on poc/photo-browser: 4dbd3f9") is left over
  from an interrupted step. Inspected 2026-09-20: it only edits the root
  `CLAUDE.md` (adds a house rule: commit **without** Co-Authored-By or session
  links). Not applied, not dropped.
