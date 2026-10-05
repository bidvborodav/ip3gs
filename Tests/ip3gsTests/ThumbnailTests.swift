import ImageIO
import XCTest
@testable import ip3gs

final class ThumbnailTests: XCTestCase {
    private func tempFile(_ data: Data, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    func testDownsamplesToTheMaxPixelKeepingAspectRatio() throws {
        let file = try tempFile(makeJPEG(width: 1000, height: 500), name: "wide.jpg")

        let data = try XCTUnwrap(Thumbnail.data(from: file))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 100)
    }

    func testNonImageReturnsNil() throws {
        let file = try tempFile(Data("not an image".utf8), name: "notes.txt")

        XCTAssertNil(Thumbnail.data(from: file))
    }
}
