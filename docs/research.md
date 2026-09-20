# Research: open questions and unverified assumptions

The defining risk of this project: **Tasks 2–4 write `ideviceinfo` and
`afcclient` argument-and-output parsing against a documented assumption, not
against observed device output.** Nothing in the codebase has met an iPhone
3GS. Task 7 exists specifically to close that gap.

This file is the list of things a real device has to settle. Keep it current —
when an assumption is confirmed or corrected, move the finding into
[`domain.md`](domain.md) and strike it here.

## Open questions

| # | Question | Where it bites if wrong |
|---|---|---|
| 1 | Does `ideviceinfo` actually emit `error code -18` on stderr for an untrusted device? | Trust detection silently degrades to "No device connected" — the user is told to plug in a phone that is already plugged in |
| 2 | Is `UniqueDeviceID:` the exact stdout key, with that spelling and colon? | Connection check never reports `.connected`; app appears permanently dead |
| 3 | Does `afcclient` accept `-u <udid> ls <path>`, and does it emit bare filenames one per line? | Listing returns empty or garbage assets |
| 4 | Does `afcclient get <remote> -` stream binary to stdout? | **Most likely to be wrong.** The current design routes binary JPEG bytes through a `String` stdout pipe, which will corrupt any non-UTF-8 payload. This probably needs `ProcessRunning` to return `Data`, not `String`. |
| 5 | Are photos on a real device confined to `/DCIM/100APPLE`? | Photos beyond the first roll are silently missed |
| 6 | Does AFC expose a cheap on-device thumbnail? | Grid pulls full-resolution JPEGs; slow and memory-hungry on a large library |

Question 4 is the one to check first. It is an architectural problem, not a
parsing tweak — it changes the `ProcessRunning` signature and every method
built on it.

## How to settle them

With a device connected and `Tools/bin/` populated:

```bash
Tools/bin/ideviceinfo                              # Q1, Q2 — also try it untrusted
Tools/bin/afcclient -u <udid> ls /DCIM             # Q5 — how many roll dirs?
Tools/bin/afcclient -u <udid> ls /DCIM/100APPLE    # Q3
Tools/bin/afcclient -u <udid> get /DCIM/100APPLE/IMG_0001.JPG - | file -   # Q4
```

When reality differs from the assumption, fix the parsing **and** update the
test fixtures to match reality. The fakes encode the assumed contract; if the
contract changes, stale fixtures will keep the tests green against a world
that does not exist.

## Research tooling

For device/protocol behavior, prefer `deepwiki` when it is available in the
session. It is not configured as a project-level MCP server, so fall back to
web search if the tool is not present.
