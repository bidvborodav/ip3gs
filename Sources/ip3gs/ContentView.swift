import SwiftUI

struct ContentView: View {
    @ObservedObject var library: PhotoLibrary

    private let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(library.statusText)
                    .font(.callout)
                if let progress = library.progress {
                    ProgressView(value: progress)
                        .accessibilityLabel("Progress")
                }
            }
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

            HStack {
                Button("Refresh") { library.startRefresh() }
                    .disabled(library.isBusy)
                Button("Download All") {
                    let destination = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Pictures/ip3gs")
                    try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    library.startDownloadAll(to: destination)
                }
                .disabled(library.assets.isEmpty || library.isBusy)
                if library.isBusy {
                    Button("Cancel") { library.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(8)
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear { library.startRefresh() }
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
                .overlay {
                    if asset.isVideo {
                        Image(systemName: "video")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Video")
                    }
                }
        }
    }
}
