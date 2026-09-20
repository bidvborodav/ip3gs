import Foundation

protocol DeviceBridging {
    func checkConnection() -> DeviceState
    func listPhotos(udid: String) -> [PhotoAsset]
    func downloadThumbnail(_ asset: PhotoAsset) -> Data?
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool
}

extension DeviceBridge: DeviceBridging {}

final class PhotoLibrary: ObservableObject {
    @Published var statusText: String = "No device connected"
    @Published var assets: [PhotoAsset] = []
    @Published var thumbnails: [String: Data] = [:]
    @Published var failedDownloads: [String] = []

    private let bridge: DeviceBridging

    init(bridge: DeviceBridging) {
        self.bridge = bridge
    }

    func refresh() {
        switch bridge.checkConnection() {
        case .notConnected:
            statusText = "No device connected"
            assets = []
        case .untrusted:
            statusText = "Trust this computer on the iPhone"
            assets = []
        case .connected(let udid):
            assets = bridge.listPhotos(udid: udid)
            for asset in assets {
                thumbnails[asset.filename] = bridge.downloadThumbnail(asset)
            }
            statusText = "\(assets.count) photo\(assets.count == 1 ? "" : "s") found"
        }
    }

    func downloadAll(to directory: URL) {
        failedDownloads = []
        var succeeded = 0

        for asset in assets {
            if bridge.download(asset, to: directory) {
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
