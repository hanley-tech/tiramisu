import SwiftUI

struct SectionDisclosure<Content: View>: View {
    let title: String
    let defaultOpen: Bool
    @ViewBuilder let content: () -> Content
    @State private var open: Bool

    init(title: String, defaultOpen: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.defaultOpen = defaultOpen
        self._open = State(initialValue: defaultOpen)
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            Divider()
        }
    }
}
