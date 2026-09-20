import XCTest

// Needs a trusted iPhone attached over USB, and takes control of the screen while it runs. Run with:
//   TEST_RUNNER_IP3GS_DEVICE=1 xcodebuild -project ip3gs.xcodeproj -scheme ip3gs \
//     -destination 'platform=macOS' test -only-testing:ip3gsUITests
// Each test launches the app with IP3GS_CACHE_DIR pointing at an empty temp directory, so loading
// starts cold (~75 s for 169 files) and the user's real cache is never touched.
final class LoadAndCancelUITests: XCTestCase {
    private var app: XCUIApplication!
    private var window: MainWindow!
    private var cacheDir: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IP3GS_DEVICE"] != nil, "set IP3GS_DEVICE to run against hardware")
        continueAfterFailure = false
        cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("ip3gs-ui-\(UUID().uuidString)")
        app = XCUIApplication()
        app.launchEnvironment["IP3GS_CACHE_DIR"] = cacheDir.path
        app.launch()
        window = MainWindow(app: app)
    }

    override func tearDown() {
        app?.terminate()
        if let cacheDir { try? FileManager.default.removeItem(at: cacheDir) }
    }

    func testLoadShowsProgressAndFillsTheGridWhileTheWindowStaysResponsive() {
        XCTAssertTrue(window.waitForStatus(prefix: "Loading", timeout: 30), "status was: \(window.statusText)")
        XCTAssertTrue(window.progress.exists, "a determinate progress bar shows while loading")
        XCTAssertTrue(window.cancelButton.exists)
        XCTAssertFalse(window.refreshButton.isEnabled)
        XCTAssertFalse(window.downloadAllButton.isEnabled)

        XCTAssertTrue(window.wait(timeout: 30) { window.thumbnailCount >= 1 }, "no thumbnail appeared")
        let early = window.thumbnailCount
        Thread.sleep(forTimeInterval: 6)
        XCTAssertGreaterThan(window.thumbnailCount, early, "thumbnails should keep arriving during the load")

        // Reaching here means the app answered accessibility queries throughout the load, so the
        // main thread was never blocked on the device.
        XCTAssertTrue(window.waitForStatus(suffix: "found", timeout: 240), "load never finished, status: \(window.statusText)")
        XCTAssertFalse(window.cancelButton.exists)
        XCTAssertFalse(window.progress.exists)
        XCTAssertTrue(window.refreshButton.isEnabled)
        XCTAssertTrue(window.downloadAllButton.isEnabled)
    }

    func testCancelStopsTheLoadCleanlyAndRefreshIsNotADeadEnd() {
        XCTAssertTrue(window.waitForStatus(prefix: "Loading", timeout: 30), "status was: \(window.statusText)")
        XCTAssertTrue(window.wait(timeout: 30) { window.thumbnailCount >= 3 })

        window.cancelButton.click()

        XCTAssertTrue(window.waitForStatus(prefix: "Cancelled", timeout: 15), "status was: \(window.statusText)")
        XCTAssertTrue(window.wait(timeout: 5) { !window.cancelButton.exists })
        XCTAssertFalse(window.progress.exists)
        XCTAssertTrue(window.refreshButton.isEnabled)
        XCTAssertTrue(window.downloadAllButton.isEnabled, "the listing survives a cancel")

        window.refreshButton.click()
        XCTAssertTrue(window.waitForStatus(prefix: "Loading", timeout: 30), "Refresh should resume loading, status: \(window.statusText)")
        XCTAssertTrue(window.cancelButton.exists)
        window.cancelButton.click()
        XCTAssertTrue(window.waitForStatus(prefix: "Cancelled", timeout: 15))
    }
}
