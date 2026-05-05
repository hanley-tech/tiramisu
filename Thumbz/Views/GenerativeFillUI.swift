import SwiftUI
import AppKit

@MainActor
enum GenerativeFillUI {
    static func present(store: DocumentStore) {
        let alert = NSAlert()
        alert.messageText = "Generative Fill"
        let hasSelection = store.selectionRect != nil
        let suggestExpand = activeLayerHasEmptyBands(store: store)
        alert.informativeText = {
            if suggestExpand { return "Active layer doesn't fill the canvas — Expand mode is preselected. Side bands will be outpainted." }
            if hasSelection { return "Mode + prompt to fill the marquee selection." }
            return "No marquee — entire canvas will be the fill region."
        }()

        // Build a compact stack: mode picker, prompt, context toggle.
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 420, height: 110))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let modeLabel = NSTextField(labelWithString: "Mode")
        let modePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        modePopup.addItem(withTitle: "Generate — fill with prompted content")
        modePopup.addItem(withTitle: "Replace — substitute what's there")
        modePopup.addItem(withTitle: "Remove — erase, fill with surroundings")
        modePopup.addItem(withTitle: "Expand — outpaint empty canvas around the layer")
        if suggestExpand { modePopup.selectItem(at: GenerativeFillMode.expand.rawValue) }
        stack.addArrangedSubview(modeLabel)
        stack.addArrangedSubview(modePopup)

        let field = NSTextField(string: "")
        field.placeholderString = "e.g., 'extend the person's left arm naturally'"
        field.frame.size.width = 420
        stack.addArrangedSubview(NSTextField(labelWithString: "Prompt (optional for Remove / Expand)"))
        stack.addArrangedSubview(field)

        stack.frame.size = NSSize(width: 420, height: 130)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let modeRaw = modePopup.indexOfSelectedItem
        let mode = GenerativeFillMode(rawValue: modeRaw) ?? .generate
        var prompt = field.stringValue
        switch mode {
        case .remove:
            if prompt.isEmpty { prompt = "natural background continuation, seamless, no objects, photorealistic" }
        case .expand:
            if prompt.isEmpty { prompt = "seamless continuation of the existing photo, matching texture, color and lighting, photorealistic" }
        default: break
        }
        let service: GenerativeFillService
        // For Expand mode, auto-upgrade the i2i local backend to the best
        // installed local mask-aware option. Order: localFlux > localSD9ch > localSD.
        // Don't override if user explicitly picked Replicate.
        let preferred: GenerativeFillSettings.Backend = {
            let chosen = GenerativeFillSettings.backend
            if mode == .expand && chosen == .localSD {
                if LocalFluxFillService.isInstalled { return .localFlux }
                if LocalSDInpaint9ChService.isModelInstalled { return .localSD9ch }
            }
            return chosen
        }()
        switch preferred {
        case .localFlux:
            guard LocalFluxFillService.isInstalled else {
                let a = NSAlert()
                a.messageText = "Local FLUX-Fill not installed"
                a.informativeText = LocalFluxFillService.setupInstructions
                a.runModal()
                return
            }
            // Default: use T9 cache if it exists (where we initially downloaded
            // the weights), otherwise let the user's HF_HOME env var win.
            let t9Cache = URL(fileURLWithPath: "/Volumes/T9/.huggingface")
            let cacheOverride = FileManager.default.fileExists(atPath: t9Cache.path) ? t9Cache : nil
            service = LocalFluxFillService(modelHFCacheDir: cacheOverride)
        case .localSD9ch:
            guard LocalSDInpaint9ChService.isModelInstalled else {
                let a = NSAlert()
                a.messageText = "Local SD inpainting model not installed"
                a.informativeText = "AI → Generative Fill Settings → Install 9ch Inpaint Model. ~2.6 GB download."
                a.runModal()
                return
            }
            service = LocalSDInpaint9ChService()
        case .localSD:
            guard LocalSDInpaintService.isModelInstalled else {
                let a = NSAlert()
                a.messageText = "Local SD model not installed"
                a.informativeText = "AI → Generative Fill Settings → Install Local Model. ~1.6 GB download."
                a.runModal()
                return
            }
            // Expand pre-fills bands with iteratively-diffused color from the
            // layer's edges. Lower strength preserves that smooth gradient
            // while letting the model add fine texture to break up flatness.
            let strength: Float = (mode == .expand) ? 0.55 : 0.85
            service = LocalSDInpaintService(modelDirectory: LocalSDInpaintService.defaultModelDirectory,
                                            strength: strength)
        case .replicate:
            if GenerativeFillSettings.apiKey.isEmpty {
                presentSettings()
                return
            }
            service = ReplicateFillService(apiKey: GenerativeFillSettings.apiKey,
                                            modelVersion: GenerativeFillSettings.model)
        }
        let win = ProgressWindow.show(title: "Generative Fill", detail: "Starting…")
        win.setIndeterminate(true)
        Task { @MainActor in
            do {
                try await GenerativeFillCoordinator.fill(store: store, mode: mode, prompt: prompt, service: service) { msg in
                    win.update(detail: msg, fraction: 0)
                }
                win.close()
            } catch {
                win.close()
                let a = NSAlert(); a.messageText = "Generative Fill failed"
                a.informativeText = error.localizedDescription
                a.alertStyle = .warning; a.runModal()
            }
        }
    }

    /// True if the active layer is a smart-object raster that doesn't already
    /// cover the full canvas — i.e. Expand mode would actually do something.
    private static func activeLayerHasEmptyBands(store: DocumentStore) -> Bool {
        guard let layer = store.activeLayer, let smart = layer.smart else { return false }
        let lw = Double(smart.pixelWidth) * smart.scaleX
        let lh = Double(smart.pixelHeight) * smart.scaleY
        let lx = smart.centerX - lw / 2
        let ly = smart.centerY - lh / 2
        let cw = store.canvasSize.width
        let ch = store.canvasSize.height
        let leftBand = lx > 1
        let rightBand = (lx + lw) < (cw - 1)
        let topBand = ly > 1
        let bottomBand = (ly + lh) < (ch - 1)
        return leftBand || rightBand || topBand || bottomBand
    }

    static func presentSettings() {
        let alert = NSAlert()
        alert.messageText = "Generative Fill Settings"
        let installed = LocalSDInpaintService.isModelInstalled
        let version = LocalSDInstaller.installedModelVersion
        let installedVersion = LocalSDInpaintService.installedVersion
        let sizeMB = installed ? Int(LocalSDInpaintService.installedSizeMB()) : 0
        let isUpToDate = installed && installedVersion == version
        let status: String = {
            if !installed { return "not installed" }
            if isUpToDate { return "installed ✓ (v\(installedVersion ?? "?"), \(sizeMB) MB)" }
            return "installed but outdated (v\(installedVersion ?? "unknown"), expected v\(version))"
        }()
        alert.informativeText = "Local SD model: \(status)"

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        // Backend picker
        let backendLabel = NSTextField(labelWithString: "Backend")
        let backendPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        backendPopup.addItem(withTitle: "Replicate (cloud, FLUX-Fill, top quality)")
        backendPopup.addItem(withTitle: "Local SD-1.5 i2i (offline, ~1.6 GB, has seam)")
        backendPopup.addItem(withTitle: "Local SD-1.5 9ch Inpaint (offline, ~2.6 GB, mask-aware ✓)")
        let fluxLabel: String = {
            if LocalFluxFillService.isInstalled {
                return "Local FLUX-Fill (offline, mflux ✓ detected, ~30 GB weights — best local quality)"
            }
            return "Local FLUX-Fill (offline, mflux NOT installed — see Help)"
        }()
        backendPopup.addItem(withTitle: fluxLabel)
        switch GenerativeFillSettings.backend {
        case .replicate:    backendPopup.selectItem(at: 0)
        case .localSD:      backendPopup.selectItem(at: 1)
        case .localSD9ch:   backendPopup.selectItem(at: 2)
        case .localFlux:    backendPopup.selectItem(at: 3)
        }
        stack.addArrangedSubview(backendLabel)
        stack.addArrangedSubview(backendPopup)

        let keyLabel = NSTextField(labelWithString: "Replicate API Key")
        let keyField = NSSecureTextField(string: GenerativeFillSettings.apiKey)
        keyField.placeholderString = "r8_..."
        keyField.frame.size.width = 420
        let modelLabel = NSTextField(labelWithString: "Replicate Model (owner/name)")
        let modelField = NSTextField(string: GenerativeFillSettings.model)
        modelField.frame.size.width = 420
        stack.addArrangedSubview(keyLabel)
        stack.addArrangedSubview(keyField)
        stack.addArrangedSubview(modelLabel)
        stack.addArrangedSubview(modelField)

        stack.frame.size = NSSize(width: 420, height: 220)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save")
        let installButtonTitle: String = {
            if !installed { return "Install Local Model…" }
            if isUpToDate { return "Reinstall Local Model" }
            return "Update Local Model"
        }()
        alert.addButton(withTitle: installButtonTitle)
        if installed {
            alert.addButton(withTitle: "Delete Local Model")
        }
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            switch backendPopup.indexOfSelectedItem {
            case 0: GenerativeFillSettings.backend = .replicate
            case 1: GenerativeFillSettings.backend = .localSD
            case 2: GenerativeFillSettings.backend = .localSD9ch
            case 3: GenerativeFillSettings.backend = .localFlux
            default: break
            }
            GenerativeFillSettings.apiKey = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            GenerativeFillSettings.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .alertSecondButtonReturn:
            installLocalModel()
        case .alertThirdButtonReturn where installed:
            deleteLocalModel()
        default: break
        }
    }

    private static func deleteLocalModel() {
        let confirm = NSAlert()
        confirm.messageText = "Delete Local SD Model?"
        confirm.informativeText = "This frees ~\(Int(LocalSDInpaintService.installedSizeMB())) MB. You'll need to reinstall to use the local backend."
        confirm.addButton(withTitle: "Delete")
        confirm.addButton(withTitle: "Cancel")
        confirm.alertStyle = .warning
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        do {
            try LocalSDInpaintService.uninstall()
            tlog("Local SD model deleted")
            // Switch backend back to replicate so Generative Fill keeps working.
            if GenerativeFillSettings.backend == .localSD {
                GenerativeFillSettings.backend = .replicate
            }
            let done = NSAlert()
            done.messageText = "Local SD model deleted."
            done.runModal()
        } catch {
            let a = NSAlert()
            a.messageText = "Delete failed"
            a.informativeText = error.localizedDescription
            a.alertStyle = .warning
            a.runModal()
        }
    }

    private static func installLocalModel() {
        var force = false
        if LocalSDInpaintService.isModelInstalled {
            let isUpToDate = LocalSDInpaintService.installedVersion == LocalSDInstaller.installedModelVersion
            if isUpToDate {
                let confirm = NSAlert()
                confirm.messageText = "Local SD model is already up to date."
                confirm.informativeText = "v\(LocalSDInstaller.installedModelVersion). Reinstall anyway? This will re-download ~1.7 GB."
                confirm.addButton(withTitle: "Reinstall")
                confirm.addButton(withTitle: "Cancel")
                confirm.alertStyle = .informational
                guard confirm.runModal() == .alertFirstButtonReturn else { return }
                force = true
            }
            // If outdated, just update — no need to ask.
        }
        let win = ProgressWindow.show(title: "Installing Local SD Model",
                                      detail: "Preparing…")
        Task { @MainActor in
            do {
                try await LocalSDInstaller.install(force: force) { msg, pct in
                    let m = msg, p = pct
                    Task { @MainActor in
                        // Throttle log spam — only log when phase changes meaningfully.
                        win.update(detail: m, fraction: p)
                    }
                }
                win.close()
                let done = NSAlert()
                done.messageText = "Local SD model installed"
                done.informativeText = "AI → Generative Fill (⌘⇧G) will now run locally on the Neural Engine."
                done.runModal()
            } catch {
                win.close()
                let a = NSAlert()
                a.messageText = "Install failed"
                a.informativeText = error.localizedDescription
                a.alertStyle = .warning
                a.runModal()
            }
        }
    }
}

/// Tiny non-blocking progress window with a determinate bar + status line.
@MainActor
final class ProgressWindow {
    private let window: NSWindow
    private let bar: NSProgressIndicator
    private let detailField: NSTextField
    private let percentField: NSTextField
    private var phaseStart: Date = Date()
    private var clockTimer: Timer?
    private var phaseLabel: String = ""

    static func show(title: String, detail: String) -> ProgressWindow {
        let w = ProgressWindow(title: title, detail: detail)
        w.window.makeKeyAndOrderFront(nil)
        return w
    }

    private init(title: String, detail: String) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 80))

        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 44, width: 420, height: 16))
        bar.isIndeterminate = false
        bar.minValue = 0; bar.maxValue = 1
        bar.doubleValue = 0
        bar.style = .bar
        content.addSubview(bar)
        self.bar = bar

        let detailField = NSTextField(labelWithString: detail)
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.frame = NSRect(x: 20, y: 18, width: 360, height: 16)
        content.addSubview(detailField)
        self.detailField = detailField

        let percentField = NSTextField(labelWithString: "0%")
        percentField.font = .systemFont(ofSize: 11, weight: .medium)
        percentField.alignment = .right
        percentField.frame = NSRect(x: 380, y: 18, width: 60, height: 16)
        content.addSubview(percentField)
        self.percentField = percentField

        self.window = NSWindow(
            contentRect: content.bounds,
            styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView = content
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        // Float above other windows (incl. our own MainWindow) so it can't
        // get hidden behind the canvas while a long generation is in flight.
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    }

    func update(detail: String, fraction: Double) {
        // Reset elapsed clock if the phase label changed.
        if detail != phaseLabel {
            phaseLabel = detail
            phaseStart = Date()
            startClockIfNeeded()
        }
        refreshDetail()
        if fraction > 0 {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
            percentField.stringValue = "\(Int(fraction * 100))%"
            stopClock()
        }
    }

    func setIndeterminate(_ value: Bool) {
        bar.isIndeterminate = value
        if value { bar.startAnimation(nil); startClockIfNeeded() }
        else { bar.stopAnimation(nil); stopClock() }
        percentField.stringValue = value ? "" : "0%"
    }

    func close() {
        stopClock()
        window.orderOut(nil)
    }

    // MARK: - elapsed-time clock

    private func startClockIfNeeded() {
        stopClock()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDetail() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func refreshDetail() {
        let elapsed = Date().timeIntervalSince(phaseStart)
        let pretty: String = {
            if elapsed < 60 { return String(format: "%.0fs", elapsed) }
            let m = Int(elapsed) / 60, s = Int(elapsed) % 60
            return "\(m)m \(s)s"
        }()
        detailField.stringValue = phaseLabel.isEmpty ? pretty : "\(phaseLabel) — \(pretty)"
    }
}
