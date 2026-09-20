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
