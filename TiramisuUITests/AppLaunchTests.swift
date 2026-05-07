import XCTest

/// XCUITest smoke tests for Tiramisu.
///
/// The app supports a `--ui-test` launch argument that:
///   - skips the first-run Welcome dialog
///   - skips the ControlServer (so port 7979 isn't held by the test runner)
///   - allows the app to quit when its last window closes
///     (normal behavior is to stay alive — that prevents `app.terminate()`
///      from completing during XCUITest teardown)
final class AppLaunchTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches Tiramisu, waits for the main window to render, captures a
    /// screenshot of the actual app (not the desktop), attaches it to the
    /// test result, and terminates cleanly. This is the visual proof that
    /// the app boots end-to-end and reaches its main editing canvas.
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test"]
        app.launch()

        XCTAssertEqual(app.state, .runningForeground,
                       "App did not reach foreground state after launch")

        // Wait for the main window to appear before snapshotting.
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10),
                      "Main window did not appear within 10s of launch")

        // Give SwiftUI one frame past first-paint to lay out tools/panels.
        Thread.sleep(forTimeInterval: 0.5)

        // Screenshot only the Tiramisu window (not the whole desktop).
        // XCUIElement.screenshot() bounds the capture to the element's frame;
        // app.screenshot() on macOS captures the entire main display.
        let windowScreenshot = mainWindow.screenshot()
        let windowAttachment = XCTAttachment(screenshot: windowScreenshot)
        windowAttachment.name = "tiramisu-main-window.png"
        windowAttachment.lifetime = .keepAlways
        add(windowAttachment)

        app.terminate()
    }
}
