import XCTest

/// Page object for the app's single window. Tests talk to this, never to raw identifiers.
struct MainWindow {
    let app: XCUIApplication

    var status: XCUIElement { app.staticTexts["status"] }
    var progress: XCUIElement { app.progressIndicators["progress"] }
    var refreshButton: XCUIElement { app.buttons["refresh"] }
    var downloadAllButton: XCUIElement { app.buttons["downloadAll"] }
    var cancelButton: XCUIElement { app.buttons["cancel"] }

    /// On macOS a SwiftUI `Text` exposes its string as the element's value; `label` is empty.
    var statusText: String { (status.value as? String) ?? status.label }
    /// Thumbnails currently on screen (the grid is lazy, so this is the visible part of it).
    var thumbnailCount: Int { app.images.matching(identifier: "thumbnail").count }

    /// Polls until `condition` holds or `timeout` passes. Every poll is an accessibility query,
    /// so a main thread blocked by device I/O would make this time out rather than return.
    @discardableResult
    func wait(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    @discardableResult
    func waitForStatus(prefix: String, timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { statusText.hasPrefix(prefix) }
    }

    @discardableResult
    func waitForStatus(suffix: String, timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { statusText.hasSuffix(suffix) }
    }
}
