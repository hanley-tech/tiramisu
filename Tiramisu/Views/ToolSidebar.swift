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
                let active = store.tool == tool
                let placeholder = !tool.isImplemented
                Button {
                    // Placeholder buttons are visually disabled but the
                    // selection still no-ops — users get a tooltip instead
                    // of a silent click.
                    guard !placeholder else { return }
                    store.tool = tool
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 40, height: 40)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(active ? Color.accentColor.opacity(0.25) : Color.clear)
                            }
                            .foregroundStyle(
                                placeholder ? Color.secondary.opacity(0.45)
                                : active ? Color.accentColor
                                : Color.primary
                            )
                        // Tiny dot in the corner of placeholder tools so users
                        // can tell at a glance "this exists but isn't wired yet"
                        // before they hover for the tooltip.
                        if placeholder {
                            Circle()
                                .fill(Color.secondary.opacity(0.55))
                                .frame(width: 5, height: 5)
                                .offset(x: -6, y: 6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(placeholder)
                .help(tool.tooltip)
            }
            Spacer()
            ColorPicker("", selection: Binding(
                get: { store.foreground.swiftUIColor },
                set: { store.foreground = ColorRGB($0.asNSColor) }
            ))
            .labelsHidden()
            .help("Paint color — used by drawing tools (coming in v0.3)")
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
    }
}
