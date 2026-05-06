import SwiftUI
import AppKit

struct InspectorView: View {
    @Environment(DocumentStore.self) private var store
    @AppStorage("ui.inspector.tab") private var tabRaw: String = Tab.properties.rawValue
    @AppStorage("ui.inspector.layersHeight") private var layersHeight: Double = 260
    private var tab: Tab {
        get { Tab(rawValue: tabRaw) ?? .properties }
    }
    enum Tab: String, CaseIterable, Identifiable { case properties, adjust, effects
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private let minLayersHeight: CGFloat = 80
    private let minTopHeight: CGFloat = 180  // tool options + tabs + a breath of content

    var body: some View {
        GeometryReader { proxy in
            let maxLayers = max(minLayersHeight, proxy.size.height - minTopHeight)
            let clamped = min(max(layersHeight, minLayersHeight), maxLayers)

            VStack(spacing: 0) {
                ToolOptionsPanel()
                    .padding(10)
                    .background(Color(nsColor: .windowBackgroundColor))

                Picker("", selection: Binding(
                    get: { tab },
                    set: { tabRaw = $0.rawValue }
                )) {
                    ForEach(Tab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case .properties: PropertiesTab()
                        case .adjust:     AdjustTab()
                        case .effects:    EffectsTab()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)

                ResizeHandle(
                    height: Binding(
                        get: { CGFloat(layersHeight) },
                        set: { layersHeight = Double($0) }
                    ),
                    minHeight: minLayersHeight,
                    maxHeight: maxLayers
                )

                LayersPanel()
                    .frame(height: clamped)
            }
        }
    }
}

private struct ResizeHandle: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @State private var startHeight: CGFloat?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            Rectangle()
                .fill(hovering ? Color.accentColor.opacity(0.25) : Color.clear)
                .frame(height: 4)
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle().fill(Color.secondary.opacity(hovering ? 0.9 : 0.5))
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
        .frame(height: 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if startHeight == nil { startHeight = height }
                    let delta = -value.translation.height
                    let candidate = (startHeight ?? height) + delta
                    height = min(max(candidate, minHeight), maxHeight)
                }
                .onEnded { _ in startHeight = nil }
        )
    }
}
