# Plan: POC milestone 1

**Goal:** everything in the POC that can be verified without a phone —
portable binaries in `Tools/bin/`, Tasks 2–6 built, `xcodebuild build` and
`test` green. Task 7 (real device) is the next milestone.

**Branch:** `worktree-poc-milestone-1` (from `poc/photo-browser`).

## Steps

1. **Task 1 — binaries.** `setup.sh` builds libplist → libimobiledevice-glue →
   libtatsu → libusbmuxd → libimobiledevice statically into a temp prefix;
   only OpenSSL comes from Homebrew (static `.a`, in a dir with no dylibs).
   Gate: `setup_test.sh` passes, including a check that both binaries link
   system libraries only.
2. **Tasks 2–6** per their briefs, then corrected where the built tool's
   source disproved the briefs (recorded in
   [`../domain.md`](../domain.md#tool-interfaces-verified-from-source)):
   - `ProcessRunning.stdout` is `Data` (photo bytes are not UTF-8) and takes a
     `stdin` argument.
   - `SystemProcessRunner` drains both pipes before `waitUntilExit()`; the
     brief's order deadlocks past the 64 KB pipe buffer.
   - `afcclient` is driven through stdin (`ls`/`get` then `quit`), with ANSI
     escapes and prompts stripped; `get` writes a local file, so
     `downloadThumbnail` reads it back from a temp dir.
   - `ideviceinfo` trust detection parses the trailing `(<code>)` and treats
     -17/-18/-19/-21 as untrusted, not an `error code -18` string.
3. One commit per task; tests written after code (TDD off for the POC).

## Out of scope

Task 7, bundling `Tools/bin` into the app, background thumbnail loading,
video filtering, roll directories beyond `100APPLE`.
