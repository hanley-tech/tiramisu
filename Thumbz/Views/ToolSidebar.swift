import SwiftUI

struct ToolSidebar: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        VStack(spacing: 4) {
            // Clear the window title bar — the traffic light cluster sits in that
            // region and would otherwise render on top of the first tool button.
            Spacer().frame(height: 28)
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
            .help("Foreground color")
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
