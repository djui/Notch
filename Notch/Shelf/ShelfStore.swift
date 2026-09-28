import AppKit
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    var url: URL

    var name: String { url.lastPathComponent }
}

/// Files dragged onto the notch, kept by reference (nothing is copied) until removed.
@Observable
@MainActor
final class ShelfStore {
    private(set) var items: [ShelfItem] = []

    private static let defaultsKey = "shelfPaths"
    static let maxItems = 12

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ShelfItem(id: UUID(), url: URL(fileURLWithPath: $0)) }
    }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url.standardizedFileURL))
        let new = urls
            .filter { $0.isFileURL && !known.contains($0.standardizedFileURL) }
            .map { ShelfItem(id: UUID(), url: $0) }
        guard !new.isEmpty else { return }
        items = Array((new + items).prefix(Self.maxItems))
        save()
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func airDrop() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: items.map(\.url))
    }

    /// Accepts file URLs from a SwiftUI drop.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, self != nil else { return }
                Task { @MainActor [weak self] in
                    self?.add([url])
                }
            }
        }
        return true
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: Self.defaultsKey)
    }
}
