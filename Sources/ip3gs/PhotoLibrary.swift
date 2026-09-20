import Foundation

protocol DeviceBridging {
    func checkConnection() -> DeviceState
    func listPhotos(udid: String) -> [PhotoAsset]
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool
}

extension DeviceBridge: DeviceBridging {}

final class PhotoLibrary: ObservableObject {
    @Published var statusText: String = "No device connected"
    @Published var assets: [PhotoAsset] = []
    @Published var thumbnails: [String: Data] = [:]
    @Published var failedDownloads: [String] = []

    private let bridge: DeviceBridging
    private let cacheRoot: URL
    private var cache: PhotoCache?

    init(bridge: DeviceBridging,
         cacheRoot: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
             .appendingPathComponent("ip3gs")) {
        self.bridge = bridge
        self.cacheRoot = cacheRoot
    }

    func refresh() {
        switch bridge.checkConnection() {
        case .notConnected:
            cache = nil
            statusText = "No device connected"
            assets = []
        case .untrusted:
            cache = nil
            statusText = "Trust this computer on the iPhone"
            assets = []
        case .connected(let udid):
            let cache = PhotoCache(directory: cacheRoot.appendingPathComponent(udid))
            self.cache = cache
            assets = bridge.listPhotos(udid: udid)
            for asset in assets where !asset.isVideo {
                if let file = cache.fill(asset, using: bridge) {
                    thumbnails[asset.filename] = try? Data(contentsOf: file)
                }
            }
            statusText = "\(assets.count) photo\(assets.count == 1 ? "" : "s") found"
        }
    }

    func downloadAll(to directory: URL) {
        failedDownloads = []
        var succeeded = 0

        for asset in assets {
            if cache?.copy(asset, to: directory) == true || bridge.download(asset, to: directory) {
                succeeded += 1
            } else {
                failedDownloads.append(asset.filename)
            }
        }

        statusText = failedDownloads.isEmpty
            ? "Downloaded \(succeeded) of \(assets.count)"
            : "Downloaded \(succeeded) of \(assets.count) (\(failedDownloads.count) failed)"
    }
}
