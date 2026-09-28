import SwiftUI
import UniformTypeIdentifiers

/// Files held on the notch. Drag one out to use it, click to open, or AirDrop them all.
struct ShelfView: View {
    var sideInset: CGFloat

    @Environment(ShelfStore.self) private var shelf
    @Environment(NotchHost.self) private var host

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                    Text("Drop files to keep them here")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(host.isDropTargeted ? 0.9 : 0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(item: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
                VStack(spacing: 8) {
                    shelfButton("AirDrop", symbol: "dot.radiowaves.left.and.right") { shelf.airDrop() }
                    shelfButton("Clear Shelf", symbol: "trash") { shelf.clear() }
                }
            }
        }
        .padding(.horizontal, sideInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shelfButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 32, height: 28)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem

    @Environment(ShelfStore.self) private var shelf

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .frame(width: 68)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(item) }
        .help(item.url.path)
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item.id) }
        }
    }
}
