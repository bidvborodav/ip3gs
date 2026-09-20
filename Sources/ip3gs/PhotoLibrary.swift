import Foundation

protocol DeviceBridging: Sendable {
    func checkConnection() -> DeviceState
    func listPhotos(udid: String) -> [PhotoAsset]
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool
}

extension DeviceBridge: DeviceBridging {}

@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var statusText: String = "No device connected"
    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var thumbnails: [String: Data] = [:]
    @Published private(set) var failedDownloads: [String] = []
    /// 0...1 while a refresh or download is running; nil otherwise.
    @Published private(set) var progress: Double?
    @Published private var task: Task<Void, Never>?

    var isBusy: Bool { task != nil }

    private let bridge: DeviceBridging
    private let cacheRoot: URL
    private var cache: PhotoCache?

    init(bridge: DeviceBridging,
         cacheRoot: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
             .appendingPathComponent("ip3gs")) {
        self.bridge = bridge
        self.cacheRoot = cacheRoot
    }

    func startRefresh() { run { await $0.refresh() } }
    func startDownloadAll(to directory: URL) { run { await $0.downloadAll(to: directory) } }
    func cancel() { task?.cancel() }

    private func run(_ work: @escaping @MainActor (PhotoLibrary) async -> Void) {
        guard task == nil else { return }
        task = Task {
            await work(self)
            task = nil
        }
    }

    // Blocking bridge calls run one at a time (each is awaited before the next starts), so the
    // USB device is never hit concurrently, and the main actor stays free while they wait.
    private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    func refresh() async {
        defer { progress = nil }
        let bridge = self.bridge
        switch await offMain({ bridge.checkConnection() }) {
        case .notConnected:
            cache = nil
            statusText = "No device connected"
            assets = []
            thumbnails = [:]
        case .untrusted:
            cache = nil
            statusText = "Trust this computer on the iPhone"
            assets = []
            thumbnails = [:]
        case .connected(let udid):
            let cache = PhotoCache(directory: cacheRoot.appendingPathComponent(udid))
            self.cache = cache
            thumbnails = [:]
            progress = 0
            assets = await offMain { bridge.listPhotos(udid: udid) }
            let pending = assets.filter { !$0.isVideo }
            for (index, asset) in pending.enumerated() {
                if Task.isCancelled {
                    statusText = "Cancelled — \(index) of \(pending.count) thumbnails loaded"
                    return
                }
                progress = Double(index) / Double(pending.count)
                statusText = "Loading \(index + 1) of \(pending.count)…"
                thumbnails[asset.filename] = await offMain {
                    cache.fill(asset, using: bridge).flatMap { try? Data(contentsOf: $0) }
                }
            }
            statusText = "\(assets.count) photo\(assets.count == 1 ? "" : "s") found"
        }
    }

    func downloadAll(to directory: URL) async {
        defer { progress = nil }
        let bridge = self.bridge
        let cache = self.cache
        failedDownloads = []
        progress = 0
        var succeeded = 0

        for (index, asset) in assets.enumerated() {
            if Task.isCancelled {
                statusText = "Cancelled — downloaded \(succeeded) of \(assets.count)"
                return
            }
            progress = Double(index) / Double(assets.count)
            statusText = "Downloading \(index + 1) of \(assets.count)…"
            let ok = await offMain {
                cache?.copy(asset, to: directory) == true || bridge.download(asset, to: directory)
            }
            if ok {
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
