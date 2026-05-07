# Testing

Tiramisu's test suite has three layers. Each verifies a different thing.

| Layer | Framework | What it proves | Speed |
|---|---|---|---|
| **Unit** | Swift Testing | Data models, codable round-trips, defaults | <50ms each |
| **Snapshot** | swift-snapshot-testing | LayerRenderer pixel output matches a golden PNG | ~200ms each |
| **UI** | XCUITest | The app actually launches and renders its main window | 5-10s each |

## Run everything

```bash
./scripts/ai-check.sh                 # unit + snapshot + HTML report (fast, default)
./scripts/ai-check.sh --with-ui       # also runs UI tests (launches the app)
./scripts/ai-check.sh --open          # open the HTML report when done
```

The script regenerates the xcodeproj, builds the app, runs tests, and writes
`build/test-report.html` — a self-contained accordion-style report with every
test's prose explanation and any attached images (snapshot goldens + UI
screenshots) embedded inline.

## Add a unit test

Drop a new `*.swift` file under `TiramisuTests/`:

```swift
import Testing
@testable import Tiramisu

@Suite("Whatever — short description")
struct MyFeatureTests {
    /// Triple-slash doc-comments above a test become "what this verifies"
    /// prose in the HTML report. Write them like a sentence to a future
    /// developer who needs to understand why the test exists.
    @Test("Memberwise init stores all four channels")
    func memberwiseInit() {
        let c = ColorRGB(r: 0.25, g: 0.5, b: 0.75)
        #expect(c.r == 0.25)
    }
}
```

Re-run `xcodegen generate` only if you added new top-level test target dependencies; otherwise just add the file and the next test run picks it up.

## Add a snapshot test

```swift
import XCTest
import SnapshotTesting
@testable import Tiramisu

@MainActor
final class MyRendererSnapshotTests: XCTestCase {
    func testSomeRender() throws {
        let cg = LayerRenderer.composite(store: makeFixture())!
        let img = NSImage(cgImage: cg, size: ...)
        assertSnapshot(of: img, as: .image(precision: 0.99))
    }
}
```

**First run**: the test fails with "No reference was found on disk." This is
expected — the renderer's output is recorded to
`TiramisuTests/__Snapshots__/MyRendererSnapshotTests/<test>.1.png`.

**Re-run**: with the golden in place, the test passes by comparing pixel-for-pixel.

**To re-record after intentional renderer changes**: delete the matching
`.png` under `__Snapshots__/` and re-run.

Goldens are committed to git — that's the whole point. A diff against the
golden is the visual regression signal.

## UI tests + the `--ui-test` launch flag

UI tests launch the actual `Tiramisu.app`. The app supports a `--ui-test`
launch argument that:

- skips the first-run Welcome dialog
- skips the ControlServer (so port 7979 isn't held during the test)
- allows the app to quit when its last window closes (the default behavior is
  to stay alive — that prevented `app.terminate()` from completing during
  XCUITest teardown)

Pass it via `app.launchArguments = ["--ui-test"]`.

Use `XCUIElement.screenshot()` on a window element (not `app.screenshot()`)
to bound the capture to the app window. `app.screenshot()` on macOS captures
the entire main display, which leaks whatever's behind the app.

## CI

`.github/workflows/test.yml` runs `./scripts/ai-check.sh` on every push
to `main` and every PR, on the `macos-26` Apple Silicon runner — same
SDK + arch as your dev machine. Both the HTML report and the xcresult
bundle are uploaded as artifacts (30-day and 14-day retention).

UI tests are skipped in CI (slow, require an active display); the
local `--with-ui` invocation covers them. If you want CI to run UI
tests too, add `--with-ui` to the `ai-check` step in test.yml.

`runs-on: macos-26` is pinned explicitly. `macos-latest` still resolves
to macos-15 at the time of writing — re-evaluate the pin annually as
GitHub rotates the alias forward.

## When tests fail

Run `./scripts/ai-check.sh --open` and read the report. Each failed test row
expands to show its prose, source file, and any attached image (including
the diff PNG that swift-snapshot-testing writes when a snapshot doesn't
match its golden).
