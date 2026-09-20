# Domain: talking to an iPhone 3GS from a modern Mac

Why this project exists: the iPhone 3GS tops out at iOS 6.1.6, and the modern
sync stack (iTunes/Photos/Image Capture) has dropped support for devices that
old. The photos are still on the device and still reachable over USB — just
not by any shipping Apple tool.

> **Confidence warning.** Almost everything below is *assumed* from
> documentation and prior art, not observed against the actual device. Items
> marked **[assumed]** have never been verified on hardware. See
> [`research.md`](research.md) for the full open-questions list.

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
and exercised against the built binaries with **no device attached**. This is
source-level truth, not device truth: what the phone itself returns is still
**[assumed]** (see [`research.md`](research.md)).

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

**[assumed]** A device with more than ~1000 photos rolls over into
`101APPLE`, `102APPLE`, and so on — so hardcoding `100APPLE` will silently
miss photos on a well-used device. This is a known, accepted POC limitation,
not an oversight; widening it is a follow-up once the single-directory path
is proven.

**[assumed]** There is no separate on-device thumbnail that AFC exposes
cheaply. The POC therefore pulls full-resolution JPEGs and uses them as
thumbnails — correct, but slow and memory-hungry on a large library. Real
thumbnailing would mean downsampling locally after the pull.

## Failure modes that matter

These are the states the UI must distinguish, because they demand different
things from the user:

| State | What the user must do | How we detect it |
|---|---|---|
| No device connected | Plug the phone in | `ideviceinfo` exits non-zero without a lockdownd error line (`ERROR: No device found!`) |
| Connected, not trusted | Tap "Trust" on the iPhone, then retry | lockdownd error code in {-17, -18, -19, -21} — code list verified from source; **[assumed]** that a real 3GS reports one of these |
| Connected and paired | Nothing | **[assumed]** `UniqueDeviceID:` present in `ideviceinfo` stdout |

Which code a real, untrusted 3GS reports is the most fragile assumption left
in trust detection. If it misbehaves on hardware, look at
`untrustedLockdownCodes` in `DeviceBridge.swift` first.

## Portability constraint

The shipped app must run on a Mac with **no Homebrew and no libimobiledevice
installed**. That makes the device-access binaries part of the product, not
part of the developer's environment — see
[`architecture.md`](architecture.md#binary-resolution-and-portability) for how
that is enforced.
