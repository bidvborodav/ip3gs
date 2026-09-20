# Task 8: Docs (after Tasks 1–6 pass)

**Files:** `docs/experiments/README.md`, `docs/domain.md`, `docs/research.md`,
`docs/architecture.md`, root `CLAUDE.md`. Keep root `CLAUDE.md` under 150 lines.

- [x] `docs/experiments/README.md`: status table gets a milestone-2 block; replace **Next step**
  with milestone 3 (Phase 0 spikes); link this plan.
- [x] `docs/architecture.md`: `PhotoLibrary` is `@MainActor`, async, one bridge call at a time;
  add `PhotoCache`; binary resolution now = `Bundle.main.url(forAuxiliaryExecutable:)` with the
  build-time `copyFiles`; delete `downloadThumbnail` from the surface listing; refresh the
  "Build state" banner.
- [x] `docs/domain.md`: video handling (listed and downloaded, never thumbnailed), the cache
  location, the untrusted-path outcome from Task 7.
- [x] `docs/research.md`: mark #7 settled; add **#8** — cache key is `udid`+filename with no
  staleness check (**[assumed]** names are never reused for different content); record the
  measured timings from Task 6.
- [x] Root `CLAUDE.md`: current state; `Tools/bin/` must be populated (`./Tools/setup.sh`) **before**
  `xcodebuild` because the build copies it into the app; drop the stale "Prerequisites (unmet)"
  block if all three are now met (they are: the milestone-1 build and tests ran).
- [x] Commit `docs: record milestone 2 results`.

Back to the [milestone 2 plan](README.md).
