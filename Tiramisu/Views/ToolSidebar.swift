import SwiftUI

struct ToolSidebar: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        // Use a List for the sidebar content — gets the standard macOS
        // sidebar material background + automatic safe-area inset for the
        // title bar (no manual 28-pt spacer needed). Traffic lights sit on
        // the same vibrancy as the rest of the sidebar = no visible seam.
        VStack(spacing: 4) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    store.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 16, weight: .regular))
                        .frame(width: 40, height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(store.tool == tool ? Color.accentColor.opacity(0.25) : Color.clear)
                        }
                        .foregroundStyle(store.tool == tool ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .help(tool.label)
            }
            Spacer()
            ColorPicker("", selection: Binding(
                get: { store.foreground.swiftUIColor },
                set: { store.foreground = ColorRGB($0.asNSColor) }
            ))
            .labelsHidden()
            .help("Paint color — used by Pencil, Pen, and other drawing tools")
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
    }
}
