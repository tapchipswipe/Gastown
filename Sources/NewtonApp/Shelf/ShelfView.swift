import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NewtonCore

public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let date: Date
    public let url: URL?

    public init(id: UUID = UUID(), title: String, detail: String, date: Date = Date(), url: URL? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.date = date
        self.url = url
    }
}

public struct ShelfView: View {
    var onDismiss: () -> Void
    @State private var items: [ShelfItem] = []
    @State private var isTargeted = false
    @Environment(\.colorScheme) private var colorScheme

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Floating Drop Shelf")
                        .font(.system(size: 12, weight: .bold))
                }

                Spacer()

                if !items.isEmpty {
                    Button("Clear") {
                        withAnimation { items.removeAll() }
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.2)

            // Content or Drop Zone
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: isTargeted ? "arrow.down.doc.fill" : "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.6))

                    Text("Drop files, images, or snippets here")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button("Paste from Clipboard") {
                        pasteClipboard()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            shelfItemRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Footer
            HStack {
                Text("\(items.count) staged items")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("+ Paste Text") {
                    pasteClipboard()
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 304, height: 400)
        .background(
            ZStack {
                HUDBackdrop(cornerRadius: 18)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : PanelSurface.border(for: colorScheme), lineWidth: isTargeted ? 2 : 1)
        )
        .onDrop(of: [.fileURL, .plainText], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func shelfItemRow(_ item: ShelfItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.url != nil ? "doc.fill" : "text.quote")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation {
                    items.removeAll { $0.id == item.id }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        let newItem = ShelfItem(
                            title: url.lastPathComponent,
                            detail: url.path,
                            url: url
                        )
                        items.insert(newItem, at: 0)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string else { return }
                    DispatchQueue.main.async {
                        let title = String(string.prefix(30)).replacingOccurrences(of: "\n", with: " ")
                        let newItem = ShelfItem(
                            title: title,
                            detail: string,
                            url: nil
                        )
                        items.insert(newItem, at: 0)
                    }
                }
            }
        }
    }

    private func pasteClipboard() {
        if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
            let title = String(string.prefix(30)).replacingOccurrences(of: "\n", with: " ")
            let newItem = ShelfItem(title: title, detail: string, url: nil)
            withAnimation { items.insert(newItem, at: 0) }
        }
    }
}
