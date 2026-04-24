import SwiftUI

struct MainWindow: View {
    @Environment(DocumentStore.self) private var store
    @AppStorage("ui.inspector.visible") private var showingInspector: Bool = true

    var body: some View {
        NavigationSplitView {
            ToolSidebar()
                .navigationSplitViewColumnWidth(min: 60, ideal: 64, max: 72)
        } detail: {
            ZStack {
                Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()
                CanvasView()
                    .padding(24)
            }
            .toolbar { CanvasToolbar(store: store) }
            .inspector(isPresented: $showingInspector) {
                InspectorView()
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .navigationTitle(titleText)
        .navigationSubtitle("\(Int(store.canvasSize.width)) × \(Int(store.canvasSize.height))")
    }
    private var titleText: String {
        let base = store.currentFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return store.isDirty ? "\(base) — Edited" : base
    }
}

private struct CanvasToolbar: ToolbarContent {
    @Bindable var store: DocumentStore
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("YouTube 1280 × 720") { setSize(1280, 720) }
                Button("FHD 1920 × 1080") { setSize(1920, 1080) }
                Button("2K 2560 × 1440") { setSize(2560, 1440) }
                Button("4K UHD 3840 × 2160") { setSize(3840, 2160) }
                Button("Square 1080 × 1080") { setSize(1080, 1080) }
                Button("Vertical 1080 × 1920") { setSize(1080, 1920) }
            } label: {
                Label("Canvas \(Int(store.canvasSize.width))×\(Int(store.canvasSize.height))",
                      systemImage: "rectangle.dashed")
            }

            ColorPicker("", selection: Binding(
                get: { store.backgroundColor.swiftUIColor },
                set: { store.backgroundColor = ColorRGB($0.asNSColor); store.invalidate() }
            ))
            .labelsHidden()
            .help("Background color")

            Menu {
                Toggle("Rule of Thirds", isOn: $store.showRuleOfThirds)
                Toggle("Golden Ratio", isOn: $store.showGoldenRatio)
                Divider()
                Toggle("YouTube Safe Area", isOn: $store.showSafeArea)
                Toggle("YouTube Rounded Corners", isOn: $store.showYTCornerRadius)
                Toggle("YouTube Duration Pill", isOn: $store.showYTDurationPill)
            } label: {
                Label("Guides", systemImage: "squareshape.split.3x3")
            }
            .help("Composition and YouTube-specific guides")
        }
    }
    @MainActor
    private func setSize(_ w: CGFloat, _ h: CGFloat) {
        tlog("setSize → \(w) × \(h)")
        store.canvasSize = CGSize(width: w, height: h)
        store.invalidate()
    }
}

extension ColorRGB {
    var swiftUIColor: Color { Color(nsColor.usingColorSpace(.sRGB) ?? .white) }
}
extension Color {
    var asNSColor: NSColor { NSColor(self) }
}
