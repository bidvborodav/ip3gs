# Task 3b: async, cancellable, with progress

> **Deviations, as built.** `isBusy` derives from the stored `Task` (a `@Published` private
> property), not from `progress`, so `refresh()`/`downloadAll()` can reset their own progress bar
> when called directly by tests. `DeviceBridge` is declared `Sendable` on the class itself (a
> retroactive conformance in another file is a warning). The responsiveness and incremental tests
> are one test. The responsiveness test was **mutation-checked**: making `offMain` run inline made
> it fail with every tick seeing all 20 thumbnails and `refresh` already finished. Testing also
> found `PhotoCache.fill` left an empty `.partial` directory after every successful pull; fixed
> with a `defer` and covered in `PhotoCacheTests`.

**Files:** modify `PhotoLibrary.swift`, `ContentView.swift`, `ip3gsApp.swift` (only if the
`@StateObject` init needs `@MainActor` help), `PhotoLibraryTests.swift`.

- [x] **Step 1: Make the seams `Sendable`.** `protocol DeviceBridging: Sendable`,
  `protocol ProcessRunning: Sendable`. `DeviceBridge` is a final class of `let`s, so it conforms
  as-is once `ProcessRunning` is `Sendable`. Test doubles that hold mutable state are
  `@unchecked Sendable` (they are only touched serially).

- [x] **Step 2: Rewrite the `PhotoLibrary` class.** Work methods are `async` and cancellable via
  the surrounding `Task`; thin `start…` wrappers own the `Task` so views never touch concurrency.

```swift
@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var statusText = "No device connected"
    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var thumbnails: [String: Data] = [:]
    @Published private(set) var failedDownloads: [String] = []
    /// 0...1 while a refresh or download runs; nil when idle. `isBusy` derives from it.
    @Published private(set) var progress: Double?

    var isBusy: Bool { progress != nil }

    private let bridge: DeviceBridging
    private let cacheRoot: URL
    private var cache: PhotoCache?
    private var task: Task<Void, Never>?

    // init as in Task 3a

    func startRefresh() { run { await $0.refresh() } }
    func startDownloadAll(to directory: URL) { run { await $0.downloadAll(to: directory) } }
    func cancel() { task?.cancel() }

    private func run(_ work: @escaping @MainActor (PhotoLibrary) async -> Void) {
        guard task == nil else { return }
        progress = 0
        task = Task {
            await work(self)
            progress = nil
            task = nil
        }
    }

    /// Runs a blocking bridge call off the main thread. One at a time by construction: callers
    /// await each result before starting the next, so the USB device is never hit concurrently.
    private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    func refresh() async {
        let bridge = self.bridge
        switch await offMain({ bridge.checkConnection() }) {
        case .notConnected:
            cache = nil; assets = []; thumbnails = [:]
            statusText = "No device connected"
        case .untrusted:
            cache = nil; assets = []; thumbnails = [:]
            statusText = "Trust this computer on the iPhone"
        case .connected(let udid):
            let cache = PhotoCache(directory: cacheRoot.appendingPathComponent(udid))
            self.cache = cache
            thumbnails = [:]
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
        let bridge = self.bridge, cache = self.cache
        failedDownloads = []
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
            if ok { succeeded += 1 } else { failedDownloads.append(asset.filename) }
        }
        statusText = failedDownloads.isEmpty
            ? "Downloaded \(succeeded) of \(assets.count)"
            : "Downloaded \(succeeded) of \(assets.count) (\(failedDownloads.count) failed)"
    }
}
```

  Note `thumbnails[...] = nil` for a failed pull is a no-op assignment of `nil` — fine, the tile
  stays a placeholder.

- [x] **Step 3: `ContentView`.**
  - Under the status text: `if let progress = library.progress { ProgressView(value: progress) }`
    with 8 pt horizontal padding.
  - Bottom bar becomes an `HStack`: **Refresh** (`library.startRefresh()`), **Download All**
    (`library.startDownloadAll(to: destination)`), both `.disabled(library.isBusy)`
    (Download All also `.disabled(library.assets.isEmpty)`); and, only `if library.isBusy`,
    **Cancel** (`library.cancel()`, `.keyboardShortcut(.cancelAction)` so Esc works).
  - `.onAppear { library.startRefresh() }`.
  - Placeholder tile: for `asset.isVideo` overlay `Image(systemName: "video")` in `.secondary`;
    give it `.accessibilityLabel("Video")`.

- [x] **Step 4: Tests** (`@MainActor final class PhotoLibraryTests`, `async` test methods; call
  `await library.refresh()` directly — the `start…` wrappers stay thin and untested).
  1. Existing behaviour tests converted to `await`.
  2. **Responsiveness:** fake bridge whose `download` does `Thread.sleep(forTimeInterval: 0.05)`
     for 20 assets. Start `let refresh = Task { await library.refresh() }` and, meanwhile,
     `for _ in 0..<10 { try await Task.sleep(nanoseconds: 20_000_000); ticks += 1 }` on the main
     actor. Assert `ticks == 10` **and** the refresh has not finished when the ticks are done —
     proof the main actor was free while the bridge blocked. (Before this task the same shape
     would hang the main actor for the full duration.)
  3. **Incremental:** in the same ticking loop as (2), record `library.thumbnails.count` at each
     tick and assert that at some tick it is strictly between 0 and 20 — thumbnails were published
     while the refresh was still running, not all at the end.
  4. **Cancel (refresh):** drive through `startRefresh()`. The fake bridge's `download` sets a flag
     after its 3rd call; the test polls that flag from the main actor (20 ms sleeps), calls
     `library.cancel()`, then waits until `library.isBusy == false`. Assert `statusText` starts with
     `"Cancelled — "`, fewer than 20 thumbnails exist (at most one more than the flag point, since
     the in-flight file is allowed to finish), and `isBusy == false`.
  5. **Cancel (download):** same shape via `startDownloadAll`; assert `statusText` starts with
     `"Cancelled — downloaded "`, the destination holds fewer files than the asset count, and no
     `.partial` directory is left in the cache.
  6. `startRefresh()` while busy is a no-op (bridge `checkConnection` called once).

- [x] **Step 5: Run the full unit suite** → `** TEST SUCCEEDED **`, then
  `xcodebuild ... build` for the app target.
- [x] **Step 6: Commit** `feat: run refresh and download off the main thread with progress and cancel`.

Back to the [milestone 2 plan](README.md).
