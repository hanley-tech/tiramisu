import SwiftUI

struct LayersPanel: View {
    @Environment(DocumentStore.self) private var store
    @State private var editingLayerID: UUID?
    @State private var editingName: String = ""

    var body: some View {
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
                set: { id in store.activeLayerID = id }
            )) {
                ForEach(Array(store.layers.reversed()), id: \.id) { layer in
                    LayerRow(
                        layer: layer,
                        isEditing: editingLayerID == layer.id,
                        draftName: $editingName,
                        beginEdit: { startEditing(layer) },
                        commitEdit: { commitEditing(layer) },
                        cancelEdit: { editingLayerID = nil }
                    )
                    .tag(layer.id as UUID?)
                    .listRowBackground(layer.id == store.activeLayerID
                                       ? Color.accentColor.opacity(0.18) : Color.clear)
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
        }
    }

    private func startEditing(_ layer: PXLayer) {
        editingName = layer.name
        editingLayerID = layer.id
    }
    private func commitEditing(_ layer: PXLayer) {
        if !editingName.isEmpty && editingName != layer.name {
            store.checkpoint("Rename Layer")
            layer.name = editingName
        }
        editingLayerID = nil
    }
}

struct LayerRow: View {
    @Environment(DocumentStore.self) private var store
    let layer: PXLayer
    let isEditing: Bool
    @Binding var draftName: String
    let beginEdit: () -> Void
    let commitEdit: () -> Void
    let cancelEdit: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Drag handle — always visible, easy to grab for reorder.
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

            Group {
                if isEditing {
                    TextField("", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($nameFocused)
                        .onSubmit { commitEdit() }
                        .onExitCommand { cancelEdit() }
                        .onChange(of: isEditing) { _, editing in
                            if editing { nameFocused = true }
                        }
                        .task { nameFocused = true }
                } else {
                    Text(layer.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .onTapGesture(count: 2) { beginEdit() }
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
