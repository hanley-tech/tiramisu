import SwiftUI

struct EffectsTab: View {
    @Environment(DocumentStore.self) private var store
    @State private var displayedID: UUID?
    private var displayedLayer: PXLayer? {
        store.layers.first(where: { $0.id == displayedID })
    }

    var body: some View {
        let _ = perfMark("EffectsTab.body")
        Group {
            if let layer = displayedLayer {
                VStack(spacing: 0) {
                    InspectorSection("Drop Shadow", defaultOpen: true) {
                        DropShadowPanel(layer: layer)
                    }
                    InspectorSection("Outer Glow", defaultOpen: false) {
                        OuterGlowPanel(layer: layer)
                    }
                    InspectorSection("Stroke", defaultOpen: false) {
                        StrokePanel(layer: layer)
                    }
                    InspectorSection("Gradient Fill", defaultOpen: false) {
                        GradientFillPanel(layer: layer)
                    }
                }
            } else {
                Text("Select a layer.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .task(id: store.activeLayerID) {
            await Task.yield()
            displayedID = store.activeLayerID
        }
    }
}

// MARK: - Drop Shadow

private struct DropShadowPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            Toggle("Enable", isOn: $layer.styles.dropShadow.enabled)
                .onChange(of: layer.styles.dropShadow.enabled) { store.invalidate() }

            InspectorRow("Color") {
                InspectorColorWell(color: Binding(
                    get: { layer.styles.dropShadow.color.swiftUIColor },
                    set: { layer.styles.dropShadow.color = ColorRGB($0.asNSColor); store.invalidate() }
                ))
            }
            InspectorRow("Opacity") {
                InspectorSlider($layer.styles.dropShadow.opacity, in: 0...1, format: .percent) { store.invalidate() }
            }
            InspectorRow("Distance") {
                InspectorSlider($layer.styles.dropShadow.distance, in: 0...160, format: .integer) { store.invalidate() }
            }
            InspectorRow("Angle") {
                InspectorSlider($layer.styles.dropShadow.angle, in: 0...360, format: .degrees) { store.invalidate() }
            }
            InspectorRow("Blur") {
                InspectorSlider($layer.styles.dropShadow.blur, in: 0...120, format: .integer) { store.invalidate() }
            }
        }
    }
}

// MARK: - Outer Glow

private struct OuterGlowPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            Toggle("Enable", isOn: $layer.styles.outerGlow.enabled)
                .onChange(of: layer.styles.outerGlow.enabled) { store.invalidate() }

            InspectorRow("Color") {
                InspectorColorWell(color: Binding(
                    get: { layer.styles.outerGlow.color.swiftUIColor },
                    set: { layer.styles.outerGlow.color = ColorRGB($0.asNSColor); store.invalidate() }
                ))
            }
            InspectorRow("Opacity") {
                InspectorSlider($layer.styles.outerGlow.opacity, in: 0...1, format: .percent) { store.invalidate() }
            }
            InspectorRow("Size") {
                InspectorSlider($layer.styles.outerGlow.size, in: 0...200, format: .integer) { store.invalidate() }
            }
            InspectorRow("Spread") {
                InspectorSlider($layer.styles.outerGlow.spread, in: 0...20, format: .integer) { store.invalidate() }
            }
        }
    }
}

// MARK: - Stroke

private struct StrokePanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            Toggle("Enable", isOn: $layer.styles.stroke.enabled)
                .onChange(of: layer.styles.stroke.enabled) { store.invalidate() }

            InspectorRow("Color") {
                InspectorColorWell(color: Binding(
                    get: { layer.styles.stroke.color.swiftUIColor },
                    set: { layer.styles.stroke.color = ColorRGB($0.asNSColor); store.invalidate() }
                ))
            }
            InspectorRow("Size") {
                InspectorSlider($layer.styles.stroke.size, in: 0...40, format: .integer) { store.invalidate() }
            }
            InspectorRow("Opacity") {
                InspectorSlider($layer.styles.stroke.opacity, in: 0...1, format: .percent) { store.invalidate() }
            }
        }
    }
}

// MARK: - Gradient Fill

private struct GradientFillPanel: View {
    @Environment(DocumentStore.self) private var store
    @Bindable var layer: PXLayer

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            Toggle("Enable", isOn: $layer.styles.gradientFill.enabled)
                .onChange(of: layer.styles.gradientFill.enabled) { store.invalidate() }

            InspectorRow("Color 1") {
                InspectorColorWell(color: Binding(
                    get: { layer.styles.gradientFill.c1.swiftUIColor },
                    set: { layer.styles.gradientFill.c1 = ColorRGB($0.asNSColor); store.invalidate() }
                ))
            }
            InspectorRow("Color 2") {
                InspectorColorWell(color: Binding(
                    get: { layer.styles.gradientFill.c2.swiftUIColor },
                    set: { layer.styles.gradientFill.c2 = ColorRGB($0.asNSColor); store.invalidate() }
                ))
            }
            InspectorRow("Angle") {
                InspectorSlider($layer.styles.gradientFill.angle, in: 0...360, format: .degrees) { store.invalidate() }
            }
            InspectorRow("Opacity") {
                InspectorSlider($layer.styles.gradientFill.opacity, in: 0...1, format: .percent) { store.invalidate() }
            }
        }
    }
}
