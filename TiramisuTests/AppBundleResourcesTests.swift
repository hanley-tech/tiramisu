import Testing
import Foundation
@testable import Tiramisu

@MainActor
@Suite("App bundle resources — what ships inside Tiramisu.app")
struct AppBundleResourcesTests {

    /// Verifies `scripts/bootstrap.sh` is actually inside the built app's
    /// Resources/. This was a bug at one point: the script was only found
    /// via the source-repo fallback path, so distributed DMG users who
    /// clicked "Install Local FLUX-Fill…" hit "bootstrap.sh not found"
    /// and were told to clone the repo. Regression of this would silently
    /// break the wizard for every DMG user, with no compile-time signal.
    @Test("bootstrap.sh ships inside the app bundle")
    func bootstrapScriptIsBundled() throws {
        // Bundle(for:) for a class declared in the Tiramisu target resolves
        // to the bundle that statically contains that class. Under @testable
        // import the type is shared with the test bundle, but the runtime
        // bundle URL still points to Tiramisu.app's bundle when the app
        // target is the host of the test runner — which is how this test
        // target is configured (depends on target: Tiramisu).
        let bundle = Bundle(for: TiramisuAppDelegate.self)
        let url = bundle.url(forResource: "bootstrap", withExtension: "sh")
        try #require(url != nil, "scripts/bootstrap.sh must ship in the app bundle")
        let path = url!.path
        #expect(FileManager.default.isReadableFile(atPath: path),
                "Bundled bootstrap.sh exists but isn't readable")
        let data = try Data(contentsOf: url!)
        #expect(data.count > 1000,
                "Bundled bootstrap.sh is suspiciously tiny (\(data.count) bytes) — copy may have failed")
        // Read just the first line up to the newline. Slicing N bytes can cut
        // mid-multibyte-char (bootstrap.sh has box-drawing chars on line 2),
        // breaking UTF-8 decode and falsely reporting "no shebang".
        let firstLine: String = {
            guard let nl = data.firstIndex(of: 0x0A) else { return "" }
            return String(data: data[..<nl], encoding: .utf8) ?? ""
        }()
        #expect(firstLine == "#!/usr/bin/env bash" || firstLine == "#!/bin/bash",
                "Bundled bootstrap.sh doesn't start with a bash shebang — got: \(firstLine)")
    }
}

@Suite("LocalFluxFillService — setup instructions stay current")
struct SetupInstructionsTests {

    /// The Hugging Face CLI was renamed `huggingface-cli` → `hf` in
    /// huggingface_hub 0.34. Our setup instructions previously referenced
    /// the deprecated name, which led every user through a broken
    /// "huggingface-cli login" path. This test guards the fix.
    @Test("setupInstructions reference the new `hf` CLI, not the deprecated `huggingface-cli`")
    func mentionsHfNotHuggingfaceCli() {
        let txt = LocalFluxFillService.setupInstructions

        #expect(txt.contains("hf auth login"),
                "Instructions should tell users to run `hf auth login`")
        // The deprecated name should not appear in user-facing copy.
        #expect(!txt.contains("huggingface-cli"),
                "Instructions still reference the deprecated `huggingface-cli` command")
    }

    /// Regression guard: the instructions used to bury the one-click path
    /// (the "Install Local FLUX-Fill…" button calls `runLocalFluxBootstrap`).
    /// Users who never read past step 1 missed it. The current copy leads
    /// with the automated path; this test fails if someone reverts to the
    /// manual-first wording.
    @Test("setupInstructions lead with the automated install path")
    func leadsWithAutomatedPath() {
        let txt = LocalFluxFillService.setupInstructions
        #expect(txt.contains("Install Local FLUX-Fill"),
                "Instructions should reference the one-click install button")
        // FLUX-Fill is non-commercial. The instructions should call this out
        // because users assuming "free" means "commercial-OK" will hit a
        // license violation. Replicate is the commercial fallback.
        #expect(txt.contains("NON-COMMERCIAL"),
                "Instructions should note the non-commercial license")
    }

    /// Verifies the install-detection function points at the path our
    /// bootstrap script writes to (~/.local/bin/mflux-generate-fill). If
    /// either side moves and they diverge, the wizard runs the install
    /// successfully but the app keeps reporting "not installed."
    @Test("LocalFluxFillService.defaultBinaryURL matches bootstrap install location")
    func binaryURLMatchesBootstrapTarget() {
        let url = LocalFluxFillService.defaultBinaryURL
        #expect(url.path.hasSuffix("/.local/bin/mflux-generate-fill"),
                "defaultBinaryURL is \(url.path) — must end in .local/bin/mflux-generate-fill")
    }
}
