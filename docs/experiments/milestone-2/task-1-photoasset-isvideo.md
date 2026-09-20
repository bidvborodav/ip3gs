# Task 1: `PhotoAsset.isVideo`

**Files:** modify `Sources/ip3gs/DeviceBridge/PhotoAsset.swift`; test in a new
`Tests/ip3gsTests/PhotoAssetTests.swift`.

- [x] **Step 1: Implement.** One definition, used by the library (skip thumbnails) and the view
  (glyph):

```swift
struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let filename: String
    let remotePath: String

    var isVideo: Bool { filename.lowercased().hasSuffix(".mov") }
}
```

- [x] **Step 2: Test.**

```swift
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
```

- [x] **Step 3: Run** `... test -only-testing:ip3gsTests/PhotoAssetTests` → passes.
- [x] **Step 4: Commit** `feat: flag video assets` (stage the two files only).

Back to the [milestone 2 plan](README.md).
