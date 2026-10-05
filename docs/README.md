# ip3gs documentation

Map of this tree. `CLAUDE.md` at the repo root stays short and points here;
anything longer than a few lines belongs in one of these files.

| Document | What lives there |
|---|---|
| [`domain.md`](domain.md) | The device world: iPhone 3GS, lockdownd, AFC, DCIM layout, trust/pairing. What we know vs. what we assume. |
| [`architecture.md`](architecture.md) | How the app is built: the three layers, their contracts, binary resolution, the error model. |
| [`best-practices.md`](best-practices.md) | Working agreements for this repo — including the ones that override Claude Code defaults. |
| [`research.md`](research.md) | Open questions and unverified assumptions. The list of things a real device has to settle. |
| [`experiments/`](experiments/README.md) | The POC itself: scope, story map, per-task implementation briefs, execution status. |

## Conventions

- One topic per file. When a file passes ~200–300 lines, promote it to a
  directory of the same name and split by sub-topic
  (`domain.md` → `domain/{afc,pairing,dcim}.md`).
- Keep status and durable knowledge separate. Knowledge goes in the topic
  files; "where we are right now" goes in
  [`experiments/README.md`](experiments/README.md).
- Mark uncertainty explicitly. This project writes a lot of code against
  *assumed* device behavior — an assumption recorded as fact is the most
  expensive kind of error here. See [`research.md`](research.md).
