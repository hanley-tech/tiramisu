import SwiftUI

struct AdjustTab: View {
    @Environment(DocumentStore.self) private var store
    var body: some View {
        if let layer = store.activeLayer {
            VStack(spacing: 0) {
                SectionDisclosure(title: "LIGHTING", defaultOpen: true) {
                    LightingPanel(layer: layer)
                }
                if layer.kind == .raster || layer.kind == .text {
                    SectionDisclosure(title: "RELIGHT", defaultOpen: false) {
                        RelightPanel(layer: layer)
                    }
                }
                if layer.kind == .raster {
                    SectionDisclosure(title: "SKIN RETOUCH", defaultOpen: false) {
                        SkinPanel(layer: layer)
                    }
                }
                SectionDisclosure(title: "FILTERS", defaultOpen: false) {
                    FiltersPanel(layer: layer)
                }
            }
        } else {
            Text("Select a layer.").foregroundStyle(.secondary).padding()
        }
    }
}

private struct LightingPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            adjRow("Brightness", \.brightness, -1...1)
            adjRow("Contrast", \.contrast, -1...1)
            adjRow("Exposure", \.exposure, -2...2)
            adjRow("Saturation", \.saturation, -1...1)
            adjRow("Warmth", \.warmth, -1...1)
            adjRow("Shadows", \.shadows, -1...1)
            adjRow("Highlights", \.highlights, -1...1)
            Button("Reset") {
                layer.adjust = Adjustments(); store.invalidate()
            }.buttonStyle(.borderless).font(.caption)
        }
    }
    @ViewBuilder private func adjRow(_ label: String, _ kp: WritableKeyPath<Adjustments, Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: Binding(
                    get: { layer.adjust[keyPath: kp] },
                    set: { layer.adjust[keyPath: kp] = $0; store.invalidate() }
                ), in: range)
                Text(String(format: "%+.2f", layer.adjust[keyPath: kp])).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
            }
        }
    }
}

private struct RelightPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable Relight", isOn: $layer.relight.enabled)
                .onChange(of: layer.relight.enabled) { store.invalidate() }
            LabeledContent("Intensity") {
                Slider(value: $layer.relight.intensity, in: 0...2)
                    .onChange(of: layer.relight.intensity) { store.invalidate() }
            }
            LabeledContent("Radius") {
                Slider(value: $layer.relight.radius, in: 0.05...1.5)
                    .onChange(of: layer.relight.radius) { store.invalidate() }
            }
            LabeledContent("Tint") {
                ColorPicker("", selection: Binding(
                    get: { layer.relight.color.swiftUIColor },
                    set: { layer.relight.color = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Ambient") {
                Slider(value: $layer.relight.ambient, in: -1...0.5)
                    .onChange(of: layer.relight.ambient) { store.invalidate() }
            }
            Divider().padding(.vertical, 2)
            LabeledContent("X") {
                Slider(value: Binding(
                    get: { layer.relight.position.x },
                    set: { layer.relight.position.x = $0; store.invalidate() }
                ), in: 0...1)
            }
            LabeledContent("Y") {
                Slider(value: Binding(
                    get: { layer.relight.position.y },
                    set: { layer.relight.position.y = $0; store.invalidate() }
                ), in: 0...1)
            }
            Text("Select the Relight tool (☀ in the sidebar) and drag on the canvas to aim the key light.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SkinPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable Skin Retouch", isOn: $layer.skin.enabled).onChange(of: layer.skin.enabled) { store.invalidate() }
            LabeledContent("Smooth") { Slider(value: $layer.skin.smooth, in: 0...1).onChange(of: layer.skin.smooth) { store.invalidate() } }
            LabeledContent("Even Tone") { Slider(value: $layer.skin.evenTone, in: 0...1).onChange(of: layer.skin.evenTone) { store.invalidate() } }
            LabeledContent("De-age") { Slider(value: $layer.skin.deage, in: 0...1).onChange(of: layer.skin.deage) { store.invalidate() } }
            LabeledContent("Glow") { Slider(value: $layer.skin.glow, in: 0...1).onChange(of: layer.skin.glow) { store.invalidate() } }
        }
    }
}

private struct FiltersPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Gaussian Blur") { Slider(value: $layer.filters.blur, in: 0...50).onChange(of: layer.filters.blur) { store.invalidate() } }
            LabeledContent("Sharpen") { Slider(value: $layer.filters.sharpen, in: 0...2).onChange(of: layer.filters.sharpen) { store.invalidate() } }
            LabeledContent("Noise") { Slider(value: $layer.filters.noise, in: 0...1).onChange(of: layer.filters.noise) { store.invalidate() } }
            Toggle("Monochrome Noise", isOn: $layer.filters.noiseMono).onChange(of: layer.filters.noiseMono) { store.invalidate() }
            LabeledContent("Pixelate") { Slider(value: $layer.filters.pixelate, in: 0...40).onChange(of: layer.filters.pixelate) { store.invalidate() } }
            LabeledContent("Hue Shift") { Slider(value: $layer.filters.hueShift, in: -180...180).onChange(of: layer.filters.hueShift) { store.invalidate() } }
        }
    }
}
