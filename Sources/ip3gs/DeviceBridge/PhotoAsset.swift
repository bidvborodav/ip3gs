struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let filename: String
    let remotePath: String

    var isVideo: Bool { filename.lowercased().hasSuffix(".mov") }
}
