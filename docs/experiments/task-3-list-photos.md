# Task 3 — `DeviceBridge.listPhotos()`

**Axis:** Interface. A new parsing interface (afcclient listing → `PhotoAsset`),
independent of connection logic.

**Files:** create `Sources/ip3gs/DeviceBridge/PhotoAsset.swift`; modify
`Sources/ip3gs/DeviceBridge/DeviceBridge.swift`; test
`Tests/ip3gsTests/DeviceBridgeListPhotosTests.swift`.

**Consumes:** `DeviceBridge(binDir:runner:)`, `ProcessRunning` (Task 2).

- [ ] **Step 1: `PhotoAsset.swift`**

```swift
struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let filename: String
    let remotePath: String
}
```

- [ ] **Step 2: add `listPhotos(udid:)`**

> **Placement:** add this method *inside* the existing
> `final class DeviceBridge { ... }` body — not as an extension. `binDir` and
> `runner` are `private`; an extension cannot reach them and will not compile.

```swift
private static let dcimPath = "/DCIM/100APPLE"

func listPhotos(udid: String) -> [PhotoAsset] {
    guard let result = try? runner.run("\(binDir)/afcclient", arguments: ["-u", udid, "ls", Self.dcimPath]) else {
        return []
    }

    return result.stdout
        .split(separator: "\n")
        .map { String($0) }
        .filter { !$0.isEmpty }
        .map { filename in
            PhotoAsset(id: filename, filename: filename, remotePath: "\(Self.dcimPath)/\(filename)")
        }
}
```

Hardcoding `100APPLE` is a known POC limitation — see
[`../domain.md`](../domain.md#photo-library-layout) and
[`../research.md`](../research.md) Q5.

- [ ] **Step 3: verification test** (after the code)

```swift
import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdout: String

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        (stdout, "", 0)
    }
}

final class DeviceBridgeListPhotosTests: XCTestCase {
    func testParsesFilenameListIntoAssets() {
        let runner = FakeRunner(stdout: "IMG_0001.JPG\nIMG_0002.JPG\n")
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)

        let assets = bridge.listPhotos(udid: "abc123")

        XCTAssertEqual(assets, [
            PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG"),
            PhotoAsset(id: "IMG_0002.JPG", filename: "IMG_0002.JPG", remotePath: "/DCIM/100APPLE/IMG_0002.JPG"),
        ])
    }

    func testEmptyListingReturnsNoAssets() {
        let runner = FakeRunner(stdout: "")
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)

        XCTAssertEqual(bridge.listPhotos(udid: "abc123"), [])
    }
}
```

- [ ] **Step 4: run** — `-only-testing:ip3gsTests/DeviceBridgeListPhotosTests` → PASS (2 tests)

- [ ] **Step 5: commit** — `feat: add DeviceBridge photo listing`
