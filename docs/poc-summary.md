# POC summary

**Status:** done (2026-09-20). Proved end to end that a modern Mac can connect to an iPhone 3GS,
list its photo library, and download it, with a minimal, responsive SwiftUI front end.

## Goal

The current sync stack (iTunes/Photos/Image Capture) has dropped support for devices as old as
the 3GS (iOS 6.1.6). The photos are still reachable over USB via `lockdownd` + AFC — just not by
any shipping Apple tool. This POC proved that path works and is usable, as the smallest slice of
a possible future native sync app.

## What shipped

Two milestones, both on top of vendored, statically-built `libimobiledevice` binaries
(`ideviceinfo`, `afcclient` — see [`architecture.md`](architecture.md#binary-resolution-and-portability)
for why they're built from source rather than taken from Homebrew).

**Milestone 1 — prove the path.** `DeviceBridge` → `PhotoLibrary` → SwiftUI, each layer
independently testable via an injectable seam (`ProcessRunning`, `DeviceBridging`). Connect, list
`/DCIM/100APPLE`, download, verified end to end on a real 3GS: 169 of 169 files, 0 failures. The
UI was functionally complete but synchronous — ~77 s/~79 s main-thread freezes on refresh and
download, binaries only found when launched from the repo root.

**Milestone 2 — make it usable.** Launch from Finder, stay responsive with the phone attached:

- Refresh and download run off the main thread (`PhotoLibrary` is `@MainActor`, bridge calls go
  through a detached task, one at a time); thumbnails and progress publish after every file.
- A per-device `PhotoCache` (`~/Library/Caches/ip3gs/<udid>/`) pulls each photo once and reuses it
  for Download All, cutting the double-pull cost roughly in half.
- Video files (`.MOV`) are listed and downloaded but no longer pulled whole just to make a grid
  tile.
- Both binaries are copied into `ip3gs.app/Contents/MacOS` at build time and resolved via
  `Bundle.main.url(forAuxiliaryExecutable:)`, so the app runs from Finder, not only the repo root.
- Cancel (checked between files, so no half-written file survives) and Refresh.

## Verified on real hardware

One iPhone 3GS (`iPhone2,1`, iOS 6.1.6), USB, already trusted.

| | Milestone 1 | Milestone 2 |
|---|---|---|
| Refresh | ~77 s (blocking) | 74 s cold, 3–5 s warm (off main thread) |
| Download All | ~79 s (blocking, full double pull) | 6 s cold (cache reused) |
| Total | ~156 s | **~80 s** (one run measured 160 s — device/USB variance, not app overhead; see [`research.md`](research.md)) |
| Files | 169 of 169, 0 failed | 169 of 169, 0 failed |
| Responsiveness | window frozen during both phases | confirmed free throughout a 72.7 s cold load (XCUITest) |
| Binaries | run from repo root only | bundled; `otool -L` shows system libraries only |

Test coverage: 45 unit tests against fakes (no phone needed), 5 `DeviceIntegrationTests` and 2
`XCUITests` (page object in `Tests/ip3gsUITests/MainWindow.swift`) gated behind `IP3GS_DEVICE`/
`TEST_RUNNER_IP3GS_DEVICE=1`.

## Known gaps (none block the POC's goal)

- **Download All was never clicked in the real window.** It's covered by the integration test
  (into a temp directory); the real button writes to the hardcoded `~/Pictures/ip3gs/`, which
  already holds the test phone's 169 files.
- **Untrusted-device path is only partly confirmed.** A real 3GS returned
  `Invalid HostID (-21)` once, transiently, on an already-trusted phone, and recovered on its own
  ~20 s later — that code is now a verified fixture. A genuinely *unpaired* phone was never
  tested; from memory only (**[assumed]**, unconfirmed), the "Trust This Computer" dialog may not
  exist before iOS 7, so iOS 6.1.6 might never present a true untrusted state. Details:
  [`domain.md`](domain.md#failure-modes-that-matter), [`research.md`](research.md).
- **Single roll only.** `/DCIM/100APPLE` is hardcoded; a device with >~1000 photos that rolled
  over into `101APPLE` would silently lose photos. Not exercised — the test phone has one roll.
- **Cache has no staleness check.** Keyed on filename only; **[assumed]** iOS never reuses an
  `IMG_nnnn` name for different content on one device.

Full detail, task-by-task: [`experiments/README.md`](experiments/README.md) and
[`experiments/milestone-2/`](experiments/milestone-2/README.md).

## Branch history

`poc/photo-browser` → `worktree-poc-milestone-1` → `poc/milestone-2-usable`, 28 commits, merged
to `main` as a fast-forward once milestone 2 was verified.

## Next

**Milestone 3 — native sync app, Phase 0 spikes.** The main open question: time one `afcclient`
session driven with many `get` commands against the current one-spawn-per-file shape. That result
decides whether an in-process `libimobiledevice` binding is ever worth building. It would change
`DeviceBridging.download`'s per-file shape, which this POC deliberately left alone.
