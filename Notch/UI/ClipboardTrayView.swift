import SwiftUI

struct ClipboardTrayView: View {
    @Environment(NotchHost.self) private var host
    @Environment(ClipboardStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NowPlayingBarView()
            header
            if store.filteredItems.isEmpty {
                emptyState
            } else {
                cardStrip
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .padding(.top, 4)
        .onChange(of: host.searchFocusGeneration) { _, _ in
            searchFocused = true
        }
        .onChange(of: host.isExpanded) { _, expanded in
            if !expanded {
                searchFocused = false
            }
        }
        .onChange(of: store.searchQuery) { _, query in
            if !query.isEmpty {
                host.pinOpen()
            }
            if let first = store.filteredItems.first {
                store.select(first)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.7))

            TextField("Search", text: Bindable(store).searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(settings.isPaused ? "Paused" : "\(store.filteredItems.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Button {
                settings.isPaused.toggle()
            } label: {
                Image(systemName: settings.isPaused ? "pause.circle.fill" : "pause.circle")
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(settings.isPaused ? "Resume capture" : "Pause capture")

            Button {
                host.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: store.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(store.searchQuery.isEmpty ? "Copy something to get started" : "No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardStrip: some View {
        CardStripView()
    }

    private func paste(_ item: ClipItem, plain: Bool = false) {
        host.pasteItem(item, plainText: plain)
    }
}

private struct CardStripView: View {
    @Environment(NotchHost.self) private var host
    @Environment(ClipboardStore.self) private var store

    @State private var position = ScrollPosition(edge: .leading)
    @State private var offsetX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var edgeVelocity: CGFloat = 0
    @State private var lastTick: Date?

    /// Auto-scroll only in this many points from the visible left/right edge.
    private let edgeZone: CGFloat = 56
    private let maxPointsPerSecond: CGFloat = 240

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: edgeVelocity == 0)) { timeline in
            strip
                .onChange(of: timeline.date) { _, date in
                    tick(at: date)
                }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(Array(store.filteredItems.enumerated()), id: \.element.id) { index, item in
                    ClipCardView(
                        item: item,
                        index: index,
                        selected: store.selectedID == item.id
                    )
                    .id(item.id)
                    .onTapGesture(count: 2) {
                        host.pasteItem(item, plainText: false)
                    }
                    .onTapGesture {
                        store.select(item)
                    }
                    .contextMenu {
                        Button("Paste") { host.pasteItem(item, plainText: false) }
                        Button("Paste as Plain Text") { host.pasteItem(item, plainText: true) }
                        Button(item.isPinned ? "Unpin" : "Pin") {
                            store.togglePin(item)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            store.delete(item)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offsetX: geometry.contentOffset.x,
                containerWidth: geometry.containerSize.width,
                contentWidth: geometry.contentSize.width
            )
        } action: { _, metrics in
            offsetX = metrics.offsetX
            containerWidth = metrics.containerWidth
            contentWidth = metrics.contentWidth
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                edgeVelocity = velocity(at: point.x)
            case .ended:
                edgeVelocity = 0
                lastTick = nil
            }
        }
        .onChange(of: store.scrollGeneration) { _, _ in
            guard let id = store.selectedID else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                position.scrollTo(id: id, anchor: .center)
            }
        }
        .onChange(of: store.searchQuery) { _, _ in
            if let id = store.filteredItems.first?.id {
                position.scrollTo(id: id, anchor: .leading)
            }
        }
    }

    private func velocity(at x: CGFloat) -> CGFloat {
        guard containerWidth > 0, contentWidth > containerWidth + 1 else { return 0 }
        if x <= edgeZone {
            let t = min(1, max(0, (edgeZone - x) / edgeZone))
            return -maxPointsPerSecond * pow(t, 1.5)
        }
        let right = containerWidth - x
        if right <= edgeZone {
            let t = min(1, max(0, (edgeZone - right) / edgeZone))
            return maxPointsPerSecond * pow(t, 1.5)
        }
        return 0
    }

    private func tick(at date: Date) {
        let dt = min(0.05, lastTick.map { date.timeIntervalSince($0) } ?? (1.0 / 60.0))
        lastTick = date
        guard edgeVelocity != 0 else { return }
        let maxOffset = max(0, contentWidth - containerWidth)
        let next = min(maxOffset, max(0, offsetX + edgeVelocity * dt))
        guard abs(next - offsetX) > 0.04 else { return }
        offsetX = next
        position.scrollTo(x: next)
    }
}

private struct ScrollMetrics: Equatable {
    var offsetX: CGFloat
    var containerWidth: CGFloat
    var contentWidth: CGFloat
}
