# ip3gs POC: Photo Browser & Downloader — Design

## Goal

Prove, end to end, that a modern Mac can connect to an iPhone 3GS, list its
photo library, and download the photos — with a minimal SwiftUI front end.
This is a proof of concept, not a product: correctness and honest failure
states matter more than polish or feature completeness.

## Constraints

| Constraint | Value | Why |
|---|---|---|
| Dependencies | No global/Homebrew installs | User requirement — project must be self-contained |
| Device protocol library | `libimobiledevice` | Only mature open-source option for pre-iOS7 AFC/lockdown |
| Integration method | Shell out to CLI tools via `Process` | Avoids C-interop build cost for a POC |
| Download destination | Fixed `~/Pictures/ip3gs/` | No folder-picker/sandbox entitlement work needed |
| Scope | List + thumbnail grid + "Download All" | Smallest complete loop; no selection, delete, or metadata editing |
| Platform | macOS 13+, SwiftUI | Matches existing `project.yml` |

## Architecture

Three layers, each independently testable:

1. **`DeviceBridge`** — wraps `Process` calls to vendored libimobiledevice
   CLI binaries. Exposes:
   - `checkConnection() -> DeviceState` (via `ideviceinfo`)
   - `listPhotos() -> [PhotoAsset]` (via `afcclient ls` on `/DCIM/*`)
   - `downloadThumbnail(_ asset:) -> Data` / `download(_ asset:, to:)` (via `afcclient get`)
2. **`PhotoLibrary`** — `ObservableObject` owning `[PhotoAsset]` and load/download
   state; the only consumer of `DeviceBridge`.
3. **SwiftUI views** — single window: connection status bar, `LazyVGrid`
   thumbnail grid, one "Download All" button. No navigation stack, no settings.

## Dependency Vendoring

- A setup script (`Tools/setup.sh`) fetches prebuilt `libimobiledevice`
  binaries (`ideviceinfo`, `afcclient`) — or builds them from source — into
  `Tools/bin/` inside the repo.
- `Tools/bin/` is gitignored; `Tools/setup.sh` is the checked-in, repeatable
  source of truth.
- `DeviceBridge` locates binaries by path relative to the app's resource
  bundle (or repo root in dev builds) — never via `$PATH` or a system install.

## Data Flow

1. App launch → `PhotoLibrary.refresh()` → `DeviceBridge.checkConnection()`.
2. If connected + paired → `DeviceBridge.listPhotos()` → populates `[PhotoAsset]`.
3. For each asset, a background task fetches a thumbnail into a temp cache
   dir; grid updates incrementally as thumbnails arrive.
4. "Download All" → iterates assets, calls `download(_:to:)` into
   `~/Pictures/ip3gs/`, reporting per-file progress in the status bar.

## Error Handling

- No modals or alerts — all state surfaces as plain text in the status bar:
  - No device connected
  - Device connected but not trusted ("Trust this computer on the iPhone")
  - Per-file download failure (skipped, listed, non-fatal to the batch)
- Failures degrade the UI, never crash the flow.

## Out of Scope (for this POC)

- Photo selection / partial download
- Delete or write-back to device
- Metadata editing, albums, video support
- Folder picker / sandboxing entitlements
- Windows/Linux support

## Testing Approach

- `DeviceBridge` output parsing is unit-testable against captured sample
  CLI output (no live device required for CI).
- `PhotoLibrary` state transitions are unit-testable with a fake `DeviceBridge`.
- End-to-end connection/listing/download requires a physical device —
  manual verification only for this POC.
