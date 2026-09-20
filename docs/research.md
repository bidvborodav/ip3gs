# Research: open questions and unverified assumptions

The defining risk of this project: **the `ideviceinfo`/`afcclient` parsing is
written against tool behavior read from source and against assumptions about
what the phone returns — never against observed device output.** Nothing in
the codebase has met an iPhone 3GS. Task 7 exists specifically to close that
gap.

Questions 1, 3 and 4 were **settled from the 1.4.0 source on 2026-09-20** (no
hardware needed) and were all answered "no" — the original design was wrong.
Findings are in [`domain.md`](domain.md#tool-interfaces-verified-from-source).

This file is the list of things a real device has to settle. Keep it current —
when an assumption is confirmed or corrected, move the finding into
[`domain.md`](domain.md) and strike it here.

## Open questions

| # | Question | Where it bites if wrong |
|---|---|---|
| 1 | ~~Does `ideviceinfo` emit `error code -18`?~~ **Settled (source):** no. It prints `… lockdownd: <text> (<code>)`; the trust-pending state is `-19`. **Open:** which code a real untrusted 3GS reports. | Trust detection degrades to "No device connected" if the phone reports a code outside {-17,-18,-19,-21} |
| 2 | Is `UniqueDeviceID:` the exact stdout key, with that spelling and colon? | Connection check never reports `.connected`; app appears permanently dead |
| 3 | ~~Does `afcclient` accept `-u <udid> ls <path>`?~~ **Settled (source):** no — commands are read from stdin, prompts pollute stdout. **Open:** does the 3GS answer `ls /DCIM/100APPLE` with bare names one per line? | Listing returns empty or garbage assets |
| 4 | ~~Does `afcclient get <remote> -` stream to stdout?~~ **Settled (source):** no — `get` writes a local file. `ProcessRunning` now returns `Data` and downloads go via a temp file. **Open:** are downloaded JPEGs byte-identical on hardware? | Corrupt or zero-length photos |
| 5 | Are photos on a real device confined to `/DCIM/100APPLE`? | Photos beyond the first roll are silently missed |
| 6 | Does AFC expose a cheap on-device thumbnail? | Grid pulls full-resolution JPEGs; slow and memory-hungry on a large library |

Fixtures in the test suite are shaped after the tool's *source* (colored
prompt, `Error:` lines on stdout), not captured from a device. Replace them
with real captures in Task 7.

## How to settle them

With a device connected and `Tools/bin/` populated:

`afcclient` reads commands from stdin and must be told to `quit`
([why](domain.md#tool-interfaces-verified-from-source)):

```bash
Tools/bin/ideviceinfo; echo "exit=$?"              # Q1, Q2 — also try it untrusted
printf 'ls /DCIM\nquit\n'              | Tools/bin/afcclient -u <udid>   # Q5 — how many roll dirs?
printf 'ls /DCIM/100APPLE\nquit\n'     | Tools/bin/afcclient -u <udid>   # Q3 — raw output, prompts and all
printf 'get -f /DCIM/100APPLE/IMG_0001.JPG /tmp\nquit\n' | Tools/bin/afcclient -u <udid>
file /tmp/IMG_0001.JPG                             # Q4 — must say JPEG image data
```

When reality differs from the assumption, fix the parsing **and** update the
test fixtures to match reality. The fakes encode the assumed contract; if the
contract changes, stale fixtures will keep the tests green against a world
that does not exist.

## Research tooling

For device/protocol behavior, prefer `deepwiki` when it is available in the
session. It is not configured as a project-level MCP server, so fall back to
web search if the tool is not present.
