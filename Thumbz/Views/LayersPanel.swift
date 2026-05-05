import SwiftUI

struct LayersPanel: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LAYERS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Paint") { store.addLayer(PXLayer(name: "Paint", kind: .raster)) }
                    Button("Text") { store.addLayer(PXLayer(name: "Text", kind: .text)) }
                    Button("Gradient") { store.addLayer(PXLayer(name: "Gradient", kind: .gradient)) }
                    Button("Solid Color") { store.addLayer(PXLayer(name: "Solid", kind: .solid)) }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).fixedSize()

                Button(action: { store.duplicateActive() }) { Image(systemName: "square.on.square") }.buttonStyle(.borderless)
                Button(action: { store.removeActive() }) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()

            List(selection: Binding(
                get: { store.activeLayerID },
                set: { newID in
                    let t0 = CFAbsoluteTimeGetCurrent()
                    store.activeLayerID = newID
                    DispatchQueue.main.async {
                        let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                        tlog("perf: select set→nextRunloop \(String(format: "%.1f", dt))ms id=\(newID?.uuidString.prefix(8) ?? "nil")")
                    }
                }
            )) {
                ForEach(Array(store.layers.reversed()), id: \.id) { layer in
                    LayerRow(layer: layer)
                        .tag(layer.id as UUID?)
                }
                .onMove { indices, newOffset in
                    var displayed = Array(store.layers.reversed())
                    displayed.move(fromOffsets: indices, toOffset: newOffset)
                    store.checkpoint("Reorder Layers")
                    store.layers = displayed.reversed()
                    store.invalidate()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onDeleteCommand {
                guard store.activeLayerID != nil else { return }
                store.removeActive()
            }
        }
    }
}

struct LayerRow: View {
    @Environment(DocumentStore.self) private var store
    let layer: PXLayer
    @State private var isEditing: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.system(size: 10))
                .frame(width: 14, height: 22)
                .help("Drag to reorder")

            Button(action: {
                layer.visible.toggle(); store.invalidate()
            }) {
                Image(systemName: layer.visible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.visible ? .primary : .secondary)
            }
            .buttonStyle(.plain)

            LayerThumbnail(layer: layer)
                .frame(width: 36, height: 22)
                .cornerRadius(3)
                .contentShape(Rectangle())
                .onTapGesture { store.activeLayerID = layer.id }

            Group {
                if isEditing {
                    TextField("", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($nameFocused)
                        .onSubmit { commitEdit() }
                        .onExitCommand { isEditing = false }
                        .task { nameFocused = true }
                } else {
                    Text(layer.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        // Order matters: register double-tap FIRST so SwiftUI
                        // disambiguates. Single tap selects, double tap renames.
                        .onTapGesture(count: 2) { beginEdit() }
                        .onTapGesture(count: 1) { store.activeLayerID = layer.id }
                }
            }

            Spacer()
            Text(kindBadge).font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") { beginEdit() }
                .keyboardShortcut(.return, modifiers: [])
            Button("Duplicate") {
                store.activeLayerID = layer.id
                store.duplicateActive()
            }.keyboardShortcut("d", modifiers: [.command])
            Divider()
            Button(layer.visible ? "Hide" : "Show") {
                layer.visible.toggle(); store.invalidate()
            }
            Button("Bring to Front") { store.moveToFront(layer.id) }
            Button("Bring Forward") { store.moveForward(layer.id) }
            Button("Send Backward") { store.moveBackward(layer.id) }
            Button("Send to Back") { store.moveToBack(layer.id) }
            Divider()
            Button("Delete", role: .destructive) {
                store.activeLayerID = layer.id
                store.removeActive()
            }.keyboardShortcut(.delete, modifiers: [.command])
        }
    }

    private func beginEdit() {
        draftName = layer.name
        isEditing = true
    }
    private func commitEdit() {
        if !draftName.isEmpty && draftName != layer.name {
            store.checkpoint("Rename Layer")
            layer.name = draftName
        }
        isEditing = false
    }

    private var kindBadge: String {
        switch layer.kind {
        case .raster: return "R"
        case .text: return "T"
        case .gradient: return "G"
        case .solid: return "S"
        }
    }
}

private struct LayerThumbnail: View {
    let layer: PXLayer
    var body: some View {
        Rectangle().fill(
            LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.15)],
                           startPoint: .top, endPoint: .bottom))
    }
}
