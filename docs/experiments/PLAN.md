# Plan: POC milestone 1

**Goal:** everything in the POC that can be verified without a phone —
portable binaries in `Tools/bin/`, Tasks 2–6 built, `xcodebuild build` and
`test` green. Task 7 (real device) is the next milestone.

**Branch:** `worktree-poc-milestone-1` (from `poc/photo-browser`).

## Steps

1. **Task 1 — binaries.** `setup.sh` builds libplist → libimobiledevice-glue →
   libtatsu → libusbmuxd → libimobiledevice statically into a temp prefix;
   only OpenSSL comes from Homebrew (static `.a`). Gate: `setup_test.sh` passes
   and `otool -L` shows no `/opt/homebrew` references.
2. **Task 2–6** per their briefs, with two deviations from the briefs:
   - `ProcessRunning.stdout` is `Data`, not `String` (research Q4).
   - `SystemProcessRunner` drains both pipes before `waitUntilExit()`; the
     brief's order deadlocks once output exceeds the 64 KB pipe buffer.
   - `afcclient get` omits `-u ""` (brief's empty udid is untested); with no
     `-u` the tool picks the first device. **[assumed]**
3. One commit per task; tests written after code (TDD off for the POC).

## Out of scope

Task 7, bundling `Tools/bin` into the app, background thumbnail loading.
