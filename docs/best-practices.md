# Working agreements

Conventions specific to this repo. Generic advice is deliberately absent —
only things that are non-obvious or that *override* a default belong here.

## TDD is disabled for the POC

The implementation plan explicitly turns off test-driven development:

> Write the implementation directly, then a single verification pass — a smoke
> test or a regression test written *after* the code, never before. Skip
> "write failing test → confirm it fails" cycles entirely; they cost more than
> they buy at this stage.

**This overrides the `superpowers:test-driven-development` skill** for work on
this plan. Do not run red-green cycles here. This is a throwaway-tolerant POC
whose riskiest unknowns are external (does the device respond the way we
assume?), not internal — tests written before the contract is observed lock in
a guess.

Tests are still required, just after the fact: every task ends with a
verification test and a passing run before its commit.

## Evidence before "done"

Neither the build nor the test command has ever completed successfully on this
machine. That makes it easy to report progress that has not been verified.

Never claim a task passes without having run its verification command and
seen the output. If a step is blocked on the environment, say it is blocked —
"written but unverified" is an honest and useful state; "done" is not.

## Assumptions must stay labelled

Large parts of this codebase are written against assumed device behavior. An
assumption recorded as fact is the most expensive error available here,
because it survives into fixtures that keep tests green against a world that
does not exist.

Mark unverified claims **[assumed]** in [`domain.md`](domain.md) and track
them in [`research.md`](research.md). When hardware settles one, correct both
the code *and* the fixtures.

## Documentation layout

- Root `CLAUDE.md` stays **under 150 lines**. It orients and points; it does
  not explain. Anything longer belongs in `docs/`.
- One topic per file under `docs/`. Past ~200–300 lines, promote the file to
  a directory and split by sub-topic (`domain.md` → `domain/afc.md`, …).
- Durable knowledge and current status live apart: knowledge in the topic
  files, "where we are right now" in
  [`experiments/README.md`](experiments/README.md).

## Project generation

`ip3gs.xcodeproj` is gitignored and does not exist in a fresh clone. Never
hand-edit it — edit `project.yml` and re-run `xcodegen generate`. Changes made
in Xcode's project editor are erased by the next generate.

## Commits

One commit per completed task, staged file-by-file, `<type>: <what changed>`.
Full rules are in the root `CLAUDE.md` — they are standing authorization and
do not need per-commit approval.
