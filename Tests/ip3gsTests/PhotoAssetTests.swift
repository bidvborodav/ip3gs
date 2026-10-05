import XCTest
@testable import ip3gs

final class PhotoAssetTests: XCTestCase {
    private func asset(_ name: String) -> PhotoAsset {
        PhotoAsset(id: name, filename: name, remotePath: "/DCIM/100APPLE/\(name)")
    }

    func testMovIsVideoRegardlessOfCase() {
        XCTAssertTrue(asset("IMG_0001.MOV").isVideo)
        XCTAssertTrue(asset("img_0001.mov").isVideo)
    }

    func testJpegIsNotVideo() {
        XCTAssertFalse(asset("IMG_0001.JPG").isVideo)
    }
}
