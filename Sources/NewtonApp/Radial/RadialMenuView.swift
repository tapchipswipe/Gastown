import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

public struct RadialSliceItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let iconName: String
    public let action: () -> Void

    public init(title: String, iconName: String, action: @escaping () -> Void) {
        self.title = title
        self.iconName = iconName
        self.action = action
    }
}

public struct RadialMenuView: View {
    let items: [RadialSliceItem]
    @Binding var highlightedIndex: Int?
    var onSelect: (RadialSliceItem) -> Void
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let radius: CGFloat = 110
    private let centerSize: CGFloat = 54

    public init(
        items: [RadialSliceItem],
        highlightedIndex: Binding<Int?>,
        onSelect: @escaping (RadialSliceItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.items = items
        self._highlightedIndex = highlightedIndex
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Background blur circle
            Circle()
                .fill(Color.black.opacity(0.65))
                .frame(width: (radius + 40) * 2, height: (radius + 40) * 2)
                .overlay(
                    Circle().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)

            // Slices
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                sliceButton(for: item, index: index)
            }

            // Center Ring / Hub
            Button {
                onDismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(PanelSurface.controlFill(for: colorScheme))
                        .frame(width: centerSize, height: centerSize)
                    Image(systemName: "atom")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .help("Newton Radial Hub (Click to close)")
        }
        .frame(width: (radius + 50) * 2, height: (radius + 50) * 2)
    }

    private func sliceButton(for item: RadialSliceItem, index: Int) -> some View {
        let count = max(items.count, 1)
        let angle = Double(index) * (2.0 * .pi / Double(count)) - (.pi / 2.0)
        let x = cos(angle) * radius
        let y = sin(angle) * radius
        let isHighlighted = highlightedIndex == index

        return Button {
            onSelect(item)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.iconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isHighlighted ? Color.white : Color.accentColor)
                Text(item.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 64)
            .background(
                Circle()
                    .fill(isHighlighted ? Color.accentColor : PanelSurface.controlFill(for: colorScheme))
            )
            .overlay(
                Circle().strokeBorder(isHighlighted ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isHighlighted ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHighlighted)
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
    }
}
