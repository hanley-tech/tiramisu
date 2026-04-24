import SwiftUI

struct EffectsTab: View {
    @Environment(DocumentStore.self) private var store
    var body: some View {
        if let layer = store.activeLayer {
            VStack(spacing: 0) {
                SectionDisclosure(title: "DROP SHADOW", defaultOpen: true) {
                    DropShadowPanel(layer: layer)
                }
                SectionDisclosure(title: "OUTER GLOW", defaultOpen: false) {
                    OuterGlowPanel(layer: layer)
                }
                SectionDisclosure(title: "STROKE", defaultOpen: false) {
                    StrokePanel(layer: layer)
                }
                SectionDisclosure(title: "GRADIENT FILL", defaultOpen: false) {
                    GradientFillPanel(layer: layer)
                }
            }
        } else {
            Text("Select a layer.").foregroundStyle(.secondary).padding()
        }
    }
}

private struct DropShadowPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable", isOn: $layer.styles.dropShadow.enabled).onChange(of: layer.styles.dropShadow.enabled) { store.invalidate() }
            LabeledContent("Color") {
                ColorPicker("", selection: Binding(
                    get: { layer.styles.dropShadow.color.swiftUIColor },
                    set: { layer.styles.dropShadow.color = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Opacity") { Slider(value: $layer.styles.dropShadow.opacity, in: 0...1).onChange(of: layer.styles.dropShadow.opacity) { store.invalidate() } }
            LabeledContent("Distance") { Slider(value: $layer.styles.dropShadow.distance, in: 0...160).onChange(of: layer.styles.dropShadow.distance) { store.invalidate() } }
            LabeledContent("Angle") { Slider(value: $layer.styles.dropShadow.angle, in: 0...360).onChange(of: layer.styles.dropShadow.angle) { store.invalidate() } }
            LabeledContent("Blur") { Slider(value: $layer.styles.dropShadow.blur, in: 0...120).onChange(of: layer.styles.dropShadow.blur) { store.invalidate() } }
        }
    }
}

private struct OuterGlowPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable", isOn: $layer.styles.outerGlow.enabled).onChange(of: layer.styles.outerGlow.enabled) { store.invalidate() }
            LabeledContent("Color") {
                ColorPicker("", selection: Binding(
                    get: { layer.styles.outerGlow.color.swiftUIColor },
                    set: { layer.styles.outerGlow.color = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Opacity") { Slider(value: $layer.styles.outerGlow.opacity, in: 0...1).onChange(of: layer.styles.outerGlow.opacity) { store.invalidate() } }
            LabeledContent("Size") { Slider(value: $layer.styles.outerGlow.size, in: 0...200).onChange(of: layer.styles.outerGlow.size) { store.invalidate() } }
            LabeledContent("Spread") { Slider(value: $layer.styles.outerGlow.spread, in: 0...20).onChange(of: layer.styles.outerGlow.spread) { store.invalidate() } }
        }
    }
}

private struct StrokePanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable", isOn: $layer.styles.stroke.enabled).onChange(of: layer.styles.stroke.enabled) { store.invalidate() }
            LabeledContent("Color") {
                ColorPicker("", selection: Binding(
                    get: { layer.styles.stroke.color.swiftUIColor },
                    set: { layer.styles.stroke.color = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Size") { Slider(value: $layer.styles.stroke.size, in: 0...40).onChange(of: layer.styles.stroke.size) { store.invalidate() } }
            LabeledContent("Opacity") { Slider(value: $layer.styles.stroke.opacity, in: 0...1).onChange(of: layer.styles.stroke.opacity) { store.invalidate() } }
        }
    }
}

private struct GradientFillPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable", isOn: $layer.styles.gradientFill.enabled).onChange(of: layer.styles.gradientFill.enabled) { store.invalidate() }
            LabeledContent("Color 1") {
                ColorPicker("", selection: Binding(
                    get: { layer.styles.gradientFill.c1.swiftUIColor },
                    set: { layer.styles.gradientFill.c1 = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Color 2") {
                ColorPicker("", selection: Binding(
                    get: { layer.styles.gradientFill.c2.swiftUIColor },
                    set: { layer.styles.gradientFill.c2 = ColorRGB($0.asNSColor); store.invalidate() }
                )).labelsHidden()
            }
            LabeledContent("Angle") { Slider(value: $layer.styles.gradientFill.angle, in: 0...360).onChange(of: layer.styles.gradientFill.angle) { store.invalidate() } }
            LabeledContent("Opacity") { Slider(value: $layer.styles.gradientFill.opacity, in: 0...1).onChange(of: layer.styles.gradientFill.opacity) { store.invalidate() } }
        }
    }
}
