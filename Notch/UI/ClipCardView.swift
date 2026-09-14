import SwiftUI
import AppKit

struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let selected: Bool

    @Environment(ClipboardStore.self) private var store
    @Environment(NotchHost.self) private var host
    @State private var exportDragStarted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text(item.kind.title)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    store.togglePin(item)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.isPinned ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary.opacity(0.78))

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 6) {
                if let name = item.sourceAppName {
                    Text(name)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.createdAt, formatter: Self.relativeFormatter)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 188, height: 196)
        .background {
            GlassCardBackground(cornerRadius: 16, selected: selected)
        }
        .overlay(alignment: .topLeading) {
            if selected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.2)
            }
        }
        .onHover { hovering in
            if hovering {
                store.select(item)
            }
        }
        .onChange(of: host.isDraggingClip) { _, dragging in
            if !dragging {
                exportDragStarted = false
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .local)
                .onChanged { value in
                    guard !exportDragStarted, !host.isDraggingClip else { return }
                    let distance = hypot(value.translation.width, value.translation.height)
                    guard distance > 10 else { return }
                    exportDragStarted = true
                    host.startDragging(item)
                }
        )
    }

    @ViewBuilder
    private var preview: some View {
        if item.kind == .color {
            colorPreview
        } else if let image = item.previewImage {
            imagePreview(image)
        } else if let rich = item.richText {
            richTextPreview(rich)
        } else if item.kind == .file, let url = item.fileURLs.first {
            fileFallback(url)
        } else if item.kind == .url {
            urlPreview
        } else {
            Text(item.previewText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(7)
                .multilineTextAlignment(.leading)
        }
    }

    private var colorPreview: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: NSColor(hex: item.colorHex ?? "") ?? .gray))
            .overlay(alignment: .bottomLeading) {
                Text(item.colorHex ?? "")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(6)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
    }

    private func imagePreview(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func richTextPreview(_ rich: NSAttributedString) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white)
            .overlay(alignment: .topLeading) {
                Text(AttributedString(rich))
                    .font(.system(size: 10))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func fileFallback(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 36, height: 36)
            Text(item.previewText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }

    private var urlPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(URL(string: item.plainText ?? "")?.host ?? "Link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(item.plainText ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
