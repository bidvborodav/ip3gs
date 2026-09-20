import SwiftUI

@main
struct ip3gsApp: App {
    @StateObject private var library = ip3gsApp.makeLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView(library: library)
        }
    }

    // UI tests point the cache at a temp directory so they start cold and never touch the real one.
    private static func makeLibrary() -> PhotoLibrary {
        let bridge = DeviceBridge()
        guard let path = ProcessInfo.processInfo.environment["IP3GS_CACHE_DIR"] else {
            return PhotoLibrary(bridge: bridge)
        }
        return PhotoLibrary(bridge: bridge, cacheRoot: URL(fileURLWithPath: path))
    }
}
