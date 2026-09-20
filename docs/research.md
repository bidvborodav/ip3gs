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
| 1 | ~~Does `ideviceinfo` emit `error code -18`?~~ **Settled (source):** no — `… lockdownd: <text> (<code>)`. **Open (hardware):** which code an *untrusted* 3GS reports. Needs an unpaired phone. | Trust detection degrades to "No device connected" if the phone reports a code outside {-17,-18,-19,-21} |
| 2 | ~~Is `UniqueDeviceID:` the stdout key?~~ **Confirmed on hardware:** `UniqueDeviceID: <40 hex>`. | — |
| 3 | ~~Does `afcclient` list bare names?~~ **Confirmed on hardware** (via stdin, prompts stripped). | — |
| 4 | ~~Do downloads survive as binary?~~ **Confirmed on hardware:** `get -f` writes byte-correct JPEGs (SOI/EOI intact, 169 of 169). | — |
| 5 | Are photos confined to `/DCIM/100APPLE`? **True for the test phone** (single roll). **Open:** a phone with >1 roll. | Photos beyond the first roll silently missed |
| 6 | ~~Does AFC expose a cheap thumbnail?~~ **Settled:** only as packed `.ithmb` containers ([`domain.md`](domain.md#photo-library-layout)); needs a decoder. | — |
| 7 | **New:** are `.MOV` files worth listing? They are pulled whole for thumbnails and downloads. | Wasted time and disk; tolerable for the POC |

**Measured on hardware** (169 files, USB, one phone): `refresh()` 77 s,
`downloadAll` 79 s — each **blocking the calling thread**, i.e. the SwiftUI
window would freeze for over a minute at launch and again on "Download All".
This is the synchronous shortcut noted in [Task 5](experiments/task-5-photo-library.md),
now quantified.

Fixtures in the unit tests are shaped after the tool's *source*, and the
listing/download shape has since been confirmed against a real device; the
untrusted-state fixture is still source-derived.

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
