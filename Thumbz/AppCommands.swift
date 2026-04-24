import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppCommands: Commands {
    @Bindable var store: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { store.performUndo() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!store.canUndo)
            Button("Redo") { store.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canRedo)
        }
        CommandGroup(replacing: .newItem) {
            Button("New") { newDocument() }
                .keyboardShortcut("n", modifiers: [.command])
            Divider()
            Button("Open…") { openDocument() }
                .keyboardShortcut("o", modifiers: [.command])
            RecentFilesMenu(store: store)
            Divider()
            Button("Place Image…") { placeImage() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: [.command])
            Button("Save As…") { saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Export PNG…") { exportPNG() }
                .keyboardShortcut("e", modifiers: [.command])
        }
        CommandMenu("AI") {
            Button("Generative Fill…") { GenerativeFillUI.present(store: store) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Generative Fill Settings…") { GenerativeFillUI.presentSettings() }
        }
        CommandMenu("Layer") {
            Button("New Paint Layer") { store.addLayer(PXLayer(name: "Paint", kind: .raster)) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Text Layer") { store.addLayer(PXLayer(name: "Text", kind: .text)) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("New Gradient Layer") { store.addLayer(PXLayer(name: "Gradient", kind: .gradient)) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("New Solid Color Layer") { store.addLayer(PXLayer(name: "Solid", kind: .solid)) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Duplicate Layer") { store.duplicateActive() }
                .keyboardShortcut("d", modifiers: [.command])
            Button("Delete Layer") { store.removeActive() }
                .keyboardShortcut(.delete, modifiers: [.command])
            Divider()
            Button("Remove Background (AI)") { Task { await removeBackground() } }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }

    // MARK: - Document

    private func newDocument() {
        if !confirmDiscardChangesIfNeeded() { return }
        store.layers.removeAll()
        store.currentFileURL = nil
        store.isDirty = false
        store.invalidate()
    }

    private func openDocument() {
        if !confirmDiscardChangesIfNeeded() { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [thumbzType, .json]
        panel.allowedFileTypes = ["thumbz", "json"]   // belt & suspenders for older selectors
        panel.allowsOtherFileTypes = true
        panel.treatsFilePackagesAsDirectories = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Open Thumbz Project"
        panel.message = "Choose a .thumbz project file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(url: url)
    }

    fileprivate func openFile(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let snap = try JSONDecoder().decode(DocumentSnapshot.self, from: data)
            store.apply(snap)
            store.currentFileURL = url
            store.isDirty = false
            store.recordRecent(url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch let DecodingError.keyNotFound(key, ctx) {
            presentError("Project is from an older build",
                         detail: "Missing key '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))\n\n\(ctx.debugDescription)")
        } catch let DecodingError.typeMismatch(type, ctx) {
            presentError("Project format mismatch",
                         detail: "Expected \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))\n\n\(ctx.debugDescription)")
        } catch let DecodingError.dataCorrupted(ctx) {
            presentError("Project file is corrupted",
                         detail: ctx.debugDescription)
        } catch {
            presentError("Could not open document", error: error)
        }
    }

    private func presentError(_ title: String, detail: String) {
        terr("\(title): \(detail)")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func save() {
        if let url = store.currentFileURL {
            writeProject(to: url)
        } else {
            saveAs()
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [thumbzType]
        panel.nameFieldStringValue = store.currentFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled.thumbz"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeProject(to: url)
        store.currentFileURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    private func writeProject(to url: URL) {
        do {
            let snap = store.makeSnapshot()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snap)
            try data.write(to: url, options: .atomic)
            store.isDirty = false
            store.recordRecent(url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            presentError("Could not save document", error: error)
        }
    }

    private func confirmDiscardChangesIfNeeded() -> Bool {
        guard store.isDirty, !store.layers.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "Continuing will discard them. Save first?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !store.isDirty
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    private func placeImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let L = PXLayer(name: url.deletingPathExtension().lastPathComponent, kind: .raster)
        L.raster = LayerRenderer.fit(cg, into: store.canvasSize)
        store.addLayer(L)
    }

    private func exportPNG() {
        guard let image = LayerRenderer.composite(store: store) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = store.currentFileURL?.deletingPathExtension().lastPathComponent ?? "thumbnail"
        panel.nameFieldStringValue += ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    private func removeBackground() async {
        guard let layer = store.activeLayer, layer.kind == .raster else {
            NSSound.beep(); tlog("Remove BG: no active raster layer"); return
        }
        // Source image: smart source first (keeps it a smart layer with alpha),
        // otherwise the layer's baked raster.
        let sourceImage: CGImage?
        if let smart = layer.smart {
            sourceImage = SmartObjectEngine.loadSource(smart)
        } else {
            sourceImage = layer.raster
        }
        guard let cg = sourceImage else {
            NSSound.beep(); tlog("Remove BG: layer has no decodable source")
            return
        }
        do {
            store.checkpoint("Remove Background")
            tlog("Remove BG: starting Vision segmentation on \(cg.width)x\(cg.height) image")
            let cutout = try await BackgroundRemover.remove(cg)
            tlog("Remove BG: cutout \(cutout.width)x\(cutout.height)")
            if layer.smart != nil {
                // Re-encode as PNG so alpha is preserved, update the smart source bytes.
                guard let pngData = LayerSnapshot.encodePNG(cutout) else {
                    tlog("Remove BG: PNG encode failed"); NSSound.beep(); return
                }
                layer.smart?.sourceBytes = pngData
                layer.smart?.sourceFormat = "png"
                // If there was a backing file, the edits live in-app (not rewritten to disk).
            } else {
                layer.raster = cutout
            }
            store.invalidate()
        } catch {
            NSSound.beep()
            terr("Remove BG failed: \(error)")
        }
    }

    private func presentError(_ title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// UTI for Thumbz project files — declared in Info.plist (UTExportedTypeDeclarations
// + CFBundleDocumentTypes). We fetch it here; `exportedAs:` is a no-op if already
// registered by the bundle, and provides a fallback if it isn't.
let thumbzType: UTType = {
    if let t = UTType("ai.taiso.thumbz.project") { return t }
    return UTType(exportedAs: "ai.taiso.thumbz.project", conformingTo: .json)
}()

// MARK: - Debug menu

struct DebugCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Show Console") { openWindow(id: "debug-console") }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Reveal Log File") { Log.shared.reveal() }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
            Button(ControlServer.shared.isRunning
                   ? "Stop Control Server (\(Int(ControlServer.shared.port)))"
                   : "Start Control Server (127.0.0.1:7979)") {
                if ControlServer.shared.isRunning {
                    ControlServer.shared.stop()
                } else {
                    if let store = ThumbzAppDelegate.shared.liveStore {
                        ControlServer.shared.start(on: 7878, store: store)
                    }
                }
            }
        }
    }
}

// MARK: - Recent Files submenu

private struct RecentFileButton: View {
    let index: Int
    let url: URL
    @Bindable var store: DocumentStore
    let opener: (URL) -> Void

    var body: some View {
        if index < 9 {
            let char = Character("\(index + 1)")
            Button(url.lastPathComponent) { handle() }
                .keyboardShortcut(KeyEquivalent(char), modifiers: [.command])
        } else {
            Button(url.lastPathComponent) { handle() }
        }
    }
    private func handle() {
        if FileManager.default.fileExists(atPath: url.path) {
            opener(url)
        } else {
            store.removeRecent(url)
            NSSound.beep()
        }
    }
}

struct RecentFilesMenu: View {
    @Bindable var store: DocumentStore

    var body: some View {
        Menu("Open Recent") {
            if store.recentFiles.isEmpty {
                Text("No Recent Files").foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.recentFiles.enumerated()), id: \.element) { index, url in
                    RecentFileButton(index: index, url: url, store: store, opener: openFileFromRecent)
                }
                Divider()
                Button("Clear Menu") { store.clearRecents() }
            }
        }
    }

    fileprivate func openFileFromRecent(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let snap = try JSONDecoder().decode(DocumentSnapshot.self, from: data)
            store.apply(snap)
            store.currentFileURL = url
            store.isDirty = false
            store.recordRecent(url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open document"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
