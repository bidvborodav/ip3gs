# Task 6 — SwiftUI views

**Axis:** Path. Happy-path UI wired to `PhotoLibrary`; no new business logic.

**Status:** Done as briefed (2026-09-20).

**Files:** modify `Sources/ip3gs/ip3gsApp.swift`, `Sources/ip3gs/ContentView.swift`.

**Produces:** no new public interface — this is the leaf UI layer.

- [ ] **Step 1: `ip3gsApp.swift`** — construct the real `DeviceBridge`-backed library

```swift
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
```

- [ ] **Step 2: rewrite `ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var library: PhotoLibrary

    private let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        VStack(spacing: 0) {
            Text(library.statusText)
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(library.assets) { asset in
                        thumbnail(for: asset)
                    }
                }
                .padding(8)
            }

            Button("Download All") {
                let destination = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Pictures/ip3gs")
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                library.downloadAll(to: destination)
            }
            .padding(8)
            .disabled(library.assets.isEmpty)
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear { library.refresh() }
    }

    @ViewBuilder
    private func thumbnail(for asset: PhotoAsset) -> some View {
        if let data = library.thumbnails[asset.filename], let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 100, height: 100)
        }
    }
}

#Preview {
    ContentView(library: PhotoLibrary(bridge: DeviceBridge()))
}
```

Note the `#Preview` constructs a real `DeviceBridge`, so opening the canvas
will shell out to the vendored binaries. If previews hang or misbehave,
that is why — a fake bridge would be the fix.

- [ ] **Step 3: build** — `xcodegen generate && xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -configuration Debug build` → `** BUILD SUCCEEDED **`

- [ ] **Step 4: full suite** — `xcodebuild ... test` → `** TEST SUCCEEDED **`
  (no new tests here; this task is the leaf UI layer)

- [ ] **Step 5: commit** — `feat: wire SwiftUI status bar, thumbnail grid, and download button`
