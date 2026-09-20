# Milestone 2 — usable POC: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax.
> **TDD is off for this POC** ([`docs/best-practices.md`](../../best-practices.md#tdd-is-disabled-for-the-poc)):
> write the code, then the test, then run, then commit. Do not run red-green cycles.

**Goal:** the app launches from Finder and stays responsive with the phone attached.

**Branch:** `poc/milestone-2-usable` (from `worktree-poc-milestone-1`, which holds all
milestone-1 code and is not merged to `main`).

**Architecture:** `DeviceBridge` stays synchronous and blocking (it is the process seam).
`PhotoLibrary` becomes `@MainActor` and runs each blocking bridge call on a background
thread, publishing after every file. A new `PhotoCache` pulls each full-size file once into
`~/Library/Caches/ip3gs/<udid>/`; thumbnails are made from it and "Download All" copies from
it. `Tools/bin` binaries are copied into `ip3gs.app/Contents/MacOS` at build time and resolved
with `Bundle.main.url(forAuxiliaryExecutable:)`.

**Tech stack:** Swift / SwiftUI, Swift concurrency, ImageIO, xcodegen `copyFiles`, XCTest.

This milestone is roughly Phase 0–1 of the native sync app, as the smallest slice.
Milestone 3 (Phase 0 spikes, chiefly one `afcclient` session doing many `get`s vs one spawn per
file) is **out of scope** — but it would change the per-file shape of `DeviceBridging.download`,
so this plan keeps that method exactly as it is.

## Tasks

| # | Task |
|---|---|
| 0 | [Worktree baseline](task-0-worktree-baseline.md) |
| 1 | [`PhotoAsset.isVideo`](task-1-photoasset-isvideo.md) |
| 2 | [`PhotoCache` (new file, no behaviour change yet)](task-2-photocache.md) |
| 3a | [`PhotoLibrary` uses the cache and skips video thumbnails (still synchronous)](task-3a-library-uses-cache.md) |
| 3b | [async, cancellable, with progress](task-3b-async-cancel-progress.md) |
| 4 | [Downsampled thumbnails (optional — see judgement calls)](task-4-downsampled-thumbnails.md) |
| 5 | [Bundle the binaries](task-5-bundle-the-binaries.md) |
| 6 | [Verify on the real device and look at the window](task-6-verify-on-device.md) |
| 7 | [Untrusted path — **needs the user**](task-7-untrusted-path.md) |
| 8 | [Docs (after Tasks 1–6 pass)](task-8-docs.md) |

## Done when

- [ ] Launched from Finder (`open`, cwd `/`) with the phone attached, the window never freezes.
- [ ] Thumbnails appear incrementally while the grid is still loading.
- [ ] All 169 files reach `~/Pictures/ip3gs/`; refresh + download total in the ~80 s range.
- [ ] Cancel stops cleanly (no crash, no half-written files, status says how far it got).
- [ ] Both bundled binaries link only system libraries.
- [ ] The window was launched and looked at (grid, status text, buttons).
- [ ] Untrusted path tried, or recorded as unreachable on this device (needs the user).

## Judgement calls made (change any of these before executing)

| Call | Why |
|---|---|
| Cache in `~/Library/Caches/ip3gs/<udid>/`, not `~/Pictures/ip3gs/` | Browsing must not write into the user's Pictures folder; the OS may reclaim caches, which is safe because the cache is re-fillable. |
| Cache key is `udid` + filename, no size/mtime check | `ls` returns bare names only. **[assumed]** iOS never reuses `IMG_nnnn` for different content on one device. Recorded in `research.md`. |
| Cache fills via a temp `.partial` dir, then `moveItem` | A kill mid-`get` must never leave a truncated file that later counts as a cache hit. |
| Cancel is checked **between files** | Worst-case latency is one file (~0.5 s). Killing `afcclient` mid-transfer is more code for no user-visible gain. |
| Thumbnails are downsampled to 200 px (Task 4) | Otherwise 163 full 2048x1536 JPEGs (~160 MB) sit in memory and each grid redraw re-decodes them — the kind of jank this milestone exists to remove. Drop Task 4 if Task 6 shows the window is fine without it. |
| Add a **Refresh** button | Without it, Cancel during the first load is a dead end and a re-plugged phone needs an app relaunch. |
| Progress = status string **plus** a `ProgressView` bar | Keeps the "one status-bar string" rule; the bar is the standard determinate-progress control (Apple HIG). |
| `downloadThumbnail` is deleted, not kept | The cache makes it dead code (YAGNI). Its tests are replaced, not ported. |

## File structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/ip3gs/DeviceBridge/PhotoAsset.swift` | modify | add `isVideo` |
| `Sources/ip3gs/PhotoCache.swift` | **create** | per-device on-disk cache: fill once, copy out |
| `Sources/ip3gs/Thumbnail.swift` | **create** | file → 200 px JPEG `Data` (Task 4) |
| `Sources/ip3gs/PhotoLibrary.swift` | modify | async, cancellable, progress; uses cache; skips video thumbnails |
| `Sources/ip3gs/ContentView.swift` | modify | progress bar, Cancel, Refresh, video glyph |
| `Sources/ip3gs/DeviceBridge/DeviceBridge.swift` | modify | bundle-relative `binDir` default; delete `downloadThumbnail` |
| `project.yml` | modify | `copyFiles` the two binaries into the app |
| `Tests/ip3gsTests/*` | modify/create | see each task |

## Self-review against the scope

| Scope item | Covered by |
|---|---|
| 1. Unblock the UI, incremental thumbnails, progress, cancel | Task 3b (+ Task 4 to keep redraws cheap; Task 6 proves it) |
| 2. Pull each photo once | Tasks 2, 3a |
| 3. Bundle the binaries | Task 5 |
| 4. Skip videos for thumbnails | Tasks 1, 3a (download unchanged) |
| 5. Look at the window | Task 6 |
| 6. Untrusted path | Task 7 (needs the user) |

**Known risks, in order of likelihood:**
1. `codeSign: true` on copied helpers or hardened runtime rejects the helpers → Task 5 Step 3/4
   catches it before any hardware time is spent.
2. `screencapture` / `osascript` blocked by macOS privacy permissions in this session →
   Task 6 falls back to asking the user, and says so.
3. Swift 6 mode turns the `Sendable` warnings into errors → Task 0 Step 3 finds out first.
4. The ~80 s estimate is off because `.MOV` pulls are large → measured and reported, not forced.
