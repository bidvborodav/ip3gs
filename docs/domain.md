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
| No device connected | Plug the phone in | `ideviceinfo` exits non-zero, no trust-specific error |
| Connected, not trusted | Tap "Trust" on the iPhone, then retry | **[assumed]** lockdownd `error code -18` on stderr |
| Connected and paired | Nothing | `UniqueDeviceID:` present in `ideviceinfo` stdout |

The `-18` detection is the single most fragile assumption in the codebase:
it is a string match against an error message, for a specific failure, on a
specific libimobiledevice version. If trust detection misbehaves on real
hardware, look here first.

## Portability constraint

The shipped app must run on a Mac with **no Homebrew and no libimobiledevice
installed**. That makes the device-access binaries part of the product, not
part of the developer's environment — see
[`architecture.md`](architecture.md#binary-resolution-and-portability) for how
that is enforced.
