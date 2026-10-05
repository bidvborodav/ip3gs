# Domain: talking to an iPhone 3GS from a modern Mac

Why this project exists: the iPhone 3GS tops out at iOS 6.1.6, and the modern
sync stack (iTunes/Photos/Image Capture) has dropped support for devices that
old. The photos are still on the device and still reachable over USB — just
not by any shipping Apple tool.

> **Confidence.** Verified on hardware 2026-09-20 against one iPhone 3GS
> (`iPhone2,1`, iOS 6.1.6, already trusted): connection check, listing,
> download. Items still marked **[assumed]** have not been observed — chiefly
> the *untrusted* path, which needs a phone that has not paired with this Mac.
> See [`research.md`](research.md) for what remains open.

## The access path

A Mac reaches an iOS device over USB through two protocol layers:

1. **lockdownd** — the device's trust/pairing daemon. Every other service is
   negotiated through it. A device that is physically connected but has not had
   "Trust This Computer" accepted will fail here, not at the USB layer.
2. **AFC** (Apple File Conduit) — the file-transfer service lockdownd hands
   you once paired. AFC exposes a restricted slice of the device filesystem:
   the media partition, not the whole disk.

`libimobiledevice` is the only mature open-source implementation that still
speaks the pre-iOS 7 dialect of these protocols, which is why it is a hard
dependency of this project. We use two of its CLI tools:

| Tool | Role here |
|---|---|
| `ideviceinfo` | Connection + trust check; source of the device UDID. |
| `afcclient` | Directory listing and file pull from the media partition. |

## Tool interfaces (verified from source)

Read from `libimobiledevice` 1.4.0 (`tools/afcclient.c`, `tools/ideviceinfo.c`)
and exercised against the built binaries — first with no device, then against
a real 3GS. Where the two disagree the device wins; they agreed here.

**`afcclient` is an interactive shell, not a subcommand CLI.**

- Positional arguments are ignored. Only `-u <udid>`, `-n`, `--container`,
  `--documents`, `-d`, `-h`, `-v` are options; commands (`ls`, `get`, `put`,
  `cd`, …) are read from **stdin**, one per line.
- It prints a colored prompt `afc:<dir> > ` (no trailing newline) to stdout
  before every command, so output must be stripped of ANSI escapes and prompts.
- Input **must end with `quit`**: at EOF the loop spins forever (`getchar()`
  returns -1, which the loop treats as a character).
- `get [-f] <remote> <local>` writes to a **local path**. There is no `-`
  for stdout, so a download is a file on disk, not a pipe.
- It exits 0 even when a command fails; failures are `Error: …` lines on
  **stdout**. Success of `get` is best confirmed by the file existing.
- `-u ""` is rejected (exit 2). With no `-u` it targets the first device found.
  With no device at all it exits 1: `No device found. …`.

**`ideviceinfo` errors** go to stderr as
`ERROR: Could not connect to lockdownd: <text> (<code>)`, or
`ERROR: No device found!` (exit 255). Lockdown codes: `-17` passcode locked,
`-18` pairing denied, `-19` **trust dialog pending**, `-21` host unknown to the
device. The code is the trailing parenthesised number; there is no
`error code -18` string.

## Photo library layout

Photos live on the media partition under `/DCIM/`, grouped into numbered
"roll" directories. The POC currently targets **`/DCIM/100APPLE`** only.

**Observed:** the test phone's `/DCIM` holds `.MISC` and one roll,
`100APPLE`, with 169 entries: 163 `IMG_*.JPG` (~1 MB, 2048x1536, EXIF intact)
and 6 `IMG_*.MOV`. Listing is bare names, one per line.

**[assumed]** A device with more than ~1000 photos rolls over into
`101APPLE`, `102APPLE`, and so on — so hardcoding `100APPLE` will silently
miss photos on a well-used device. Not exercised: this phone has a single
roll. A known, accepted POC limitation.

**Videos share the roll.** `.MOV` files are listed like photos. The app lists
and downloads them, but does **not** pull them for grid thumbnails (the tile is
a placeholder with a video glyph); on the test phone that is 6 of 169 files.
They are pulled once, straight to the destination, by Download All.

**Thumbnails.** AFC does expose on-device thumbnails, but as packed
`/PhotoData/Thumbnails/{79x79,120x120}.ithmb` container files indexed by
`/PhotoData/Photos.sqlite`, not one JPEG per photo — using them means writing
an `.ithmb` decoder. The app instead pulls each full-resolution JPEG **once**
into a per-device cache, downsamples it for the grid, and reuses the cached file
for Download All. **Measured (2026-09-20, 169 files, one phone):** cold
refresh 74 s (163 JPEGs, ~0.45 s each) + Download All 6 s (6 videos pulled, 163
copied) = 80 s; a warm refresh takes 3–5 s. Per-file device time is **not
constant**: an earlier run the same day took 152 s + 8 s = 160 s (~0.93 s per
file, confirmed with raw `afcclient` gets in a shell, so not app overhead).

## Failure modes that matter

These are the states the UI must distinguish, because they demand different
things from the user:

| State | What the user must do | How we detect it |
|---|---|---|
| No device connected | Plug the phone in | `ideviceinfo` exits non-zero without a lockdownd error line (`ERROR: No device found!`) |
| Connected, not trusted | Tap "Trust" on the iPhone, then retry | lockdownd error code in {-17, -18, -19, -21} — code list verified from source; **[assumed]** that a real 3GS reports one of these |
| Connected and paired | Nothing | `UniqueDeviceID: <40 hex>` present in `ideviceinfo` stdout (observed) |

The *untrusted* row has only been seen once on hardware, and not the way it was
planned. On 2026-09-20, partway through a long session on an already-trusted
phone, `ideviceinfo` and `afcclient` began failing with
`ERROR: Could not connect to lockdownd: Invalid HostID (-21)`. About 20 s later
the same phone accepted this Mac again with no action from anyone. So:

- **-21 is real** and is in the untrusted set (fixture in
  `DeviceBridgeConnectionTests`, exit code not captured).
- **It can be transient on a trusted phone**, in which case the app shows
  "Trust this computer on the iPhone" although nothing needs trusting.
  **[assumed]** cause: something else talking to the device at the same time
  (Finder shows the phone in its sidebar); not established.
- **-17/-18/-19 remain source-derived.** **[assumed, from memory]** the "Trust
  This Computer" dialog arrived in iOS 7, so an iOS 6.1.6 3GS may never present
  a genuine untrusted state; this is unconfirmed.

If trust detection misbehaves, look at `untrustedLockdownCodes` in
`DeviceBridge.swift` first.

## Portability constraint

The shipped app must run on a Mac with **no Homebrew and no libimobiledevice
installed**. That makes the device-access binaries part of the product, not
part of the developer's environment — see
[`architecture.md`](architecture.md#binary-resolution-and-portability) for how
that is enforced.
