import SwiftUI
import AppKit

@MainActor
enum GenerativeFillUI {
    static func present(store: DocumentStore) {
        let alert = NSAlert()
        alert.messageText = "Generative Fill"
        let hasSelection = store.selectionRect != nil
        let layer = store.activeLayer
        let canRun = layer?.smart != nil
        if !canRun {
            alert.informativeText = "Drop an image as a Smart Object first."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        alert.informativeText = hasSelection
            ? "Describe what to generate inside the marquee selection."
            : "No selection — the entire image will be regenerated. (Use the Marquee tool to constrain.)"
        let field = NSTextField(string: "")
        field.placeholderString = "e.g., 'extend the person's left arm naturally'"
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let prompt = field.stringValue
        if GenerativeFillSettings.apiKey.isEmpty {
            presentSettings()
            return
        }
        let service = ReplicateFillService(apiKey: GenerativeFillSettings.apiKey,
                                            modelVersion: GenerativeFillSettings.model)
        Task { @MainActor in
            do {
                try await GenerativeFillCoordinator.fill(store: store, prompt: prompt, service: service)
            } catch {
                let a = NSAlert(); a.messageText = "Generative Fill failed"
                a.informativeText = error.localizedDescription
                a.alertStyle = .warning; a.runModal()
            }
        }
    }

    static func presentSettings() {
        let alert = NSAlert()
        alert.messageText = "Generative Fill Settings"
        alert.informativeText = "Replicate API key (stored locally in UserDefaults). Get one at replicate.com/account/api-tokens"
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 380, height: 60))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let keyLabel = NSTextField(labelWithString: "API Key")
        let keyField = NSSecureTextField(string: GenerativeFillSettings.apiKey)
        keyField.placeholderString = "r8_..."
        keyField.frame.size.width = 380
        let modelLabel = NSTextField(labelWithString: "Model (owner/name)")
        let modelField = NSTextField(string: GenerativeFillSettings.model)
        modelField.frame.size.width = 380
        stack.addArrangedSubview(keyLabel)
        stack.addArrangedSubview(keyField)
        stack.addArrangedSubview(modelLabel)
        stack.addArrangedSubview(modelField)
        stack.frame.size = NSSize(width: 380, height: 100)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            GenerativeFillSettings.apiKey = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            GenerativeFillSettings.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
