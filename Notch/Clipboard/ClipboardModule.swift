import SwiftUI

@MainActor
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    let title = "Clipboard"
    let symbolName = "clipboard"

    private let store: ClipboardStore
    private weak var host: NotchHost?
    private let settings: AppSettings

    init(store: ClipboardStore, host: NotchHost, settings: AppSettings) {
        self.store = store
        self.host = host
        self.settings = settings
    }

    func expandedView() -> AnyView {
        AnyView(
            ClipboardTrayView()
                .environment(store)
                .environment(settings)
                .environment(host ?? AppModel.shared.host)
        )
    }
}
