# Task 2: `PhotoCache` (new file, no behaviour change yet)

**Files:** create `Sources/ip3gs/PhotoCache.swift`, `Tests/ip3gsTests/PhotoCacheTests.swift`.

The cache takes the bridge only for the miss path, so it is testable with a fake bridge and a
temp directory.

- [x] **Step 1: Implement.**

```swift
import Foundation

/// On-disk copy of full-size downloads for one device. Pull once, reuse for thumbnails and
/// "Download All". Cache key is the filename — see research.md #8 for the staleness assumption.
struct PhotoCache: Sendable {
    let directory: URL

    func file(for asset: PhotoAsset) -> URL {
        directory.appendingPathComponent(asset.filename)
    }

    func contains(_ asset: PhotoAsset) -> Bool {
        FileManager.default.fileExists(atPath: file(for: asset).path)
    }

    /// Returns the cached file, pulling it from the device on a miss. nil if the pull fails.
    /// The pull lands in `.partial` first so an interrupted `get` is never mistaken for a hit.
    func fill(_ asset: PhotoAsset, using bridge: DeviceBridging) -> URL? {
        if contains(asset) { return file(for: asset) }
        let partial = directory.appendingPathComponent(".partial")
        let fm = FileManager.default
        try? fm.removeItem(at: partial)
        guard (try? fm.createDirectory(at: partial, withIntermediateDirectories: true)) != nil,
              bridge.download(asset, to: partial),
              (try? fm.moveItem(at: partial.appendingPathComponent(asset.filename), to: file(for: asset))) != nil
        else { return nil }
        return file(for: asset)
    }

    /// Copies a cached file into `destination`, replacing any file already there. False on a miss.
    func copy(_ asset: PhotoAsset, to destination: URL) -> Bool {
        guard contains(asset) else { return false }
        let target = destination.appendingPathComponent(asset.filename)
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        return (try? fm.copyItem(at: file(for: asset), to: target)) != nil
    }
}
```

- [x] **Step 2: Tests** (temp dir per test, a small fake `DeviceBridging` that writes bytes into the
  `directory` it is handed and counts calls). Cover:
  1. `fill` on a miss calls `bridge.download` once and returns a file with the fake's bytes.
  2. `fill` on a hit does **not** call the bridge.
  3. `fill` when `bridge.download` returns false returns nil and leaves no file in the cache.
  4. A stale `.partial/IMG.JPG` from an earlier interrupted run is not treated as a hit and
     is replaced.
  5. `copy` on a hit writes the file to the destination (also over an existing file); `copy` on a
     miss returns false.

  `DeviceBridging` still has `downloadThumbnail` at this point — the fake must implement it
  (Task 3a deletes it).

- [x] **Step 3: Run** `-only-testing:ip3gsTests/PhotoCacheTests` → passes.
- [x] **Step 4: Commit** `feat: add per-device photo cache`.

Back to the [milestone 2 plan](README.md).
