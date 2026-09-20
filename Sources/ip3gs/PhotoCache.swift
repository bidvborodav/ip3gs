import Foundation

/// On-disk copy of full-size downloads for one device. Pull once, reuse for thumbnails and
/// "Download All". The cache key is the filename; see docs/research.md for the staleness assumption.
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
