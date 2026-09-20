import SwiftUI

@main
struct ip3gsApp: App {
    @StateObject private var library = PhotoLibrary(bridge: DeviceBridge())

    var body: some Scene {
        WindowGroup {
            ContentView(library: library)
        }
    }
}
