import AppKit
import SwiftUI

@Observable
@MainActor
final class NotchHost {
    private(set) var geometry: NotchGeometry
    private(set) var isExpanded = false
    private(set) var isPinned = false
    private(set) var isHoverPeeking = false
    private(set) var visualSize: CGSize
    private(set) var modules: [any NotchModule] = []
    var selectedModuleID: String?
    var searchFocusGeneration = 0
    private(set) var isDraggingClip = false
    private(set) var suppressHoverExpand = false
    private(set) var panelFrameIsExpanded = false
    private(set) var layoutGeneration = 0

    var selectedModule: (any NotchModule)? {
        if let selectedModuleID {
            return modules.first { $0.id == selectedModuleID } ?? modules.first
        }
        return modules.first
    }

    private var panel: NotchPanel?
    private var hostingView: NSView?
    private var collapseWorkItem: DispatchWorkItem?
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalHoverMonitor: Any?
    private var localHoverMonitor: Any?
    private var isMouseInHoverTarget = false
    private var collapseWindowWorkItem: DispatchWorkItem?
    private var draggingSource: ClipDraggingSource?
    private var visibility: NotchVisibility?

    init() {
        let geometry = NotchGeometry.current(style: .notch)
        self.geometry = geometry
        visualSize = geometry.collapsedSize
    }

    func install(module: any NotchModule) {
        if modules.contains(where: { $0.id == module.id }) { return }
        modules.append(module)
        if selectedModuleID == nil {
            selectedModuleID = module.id
        }
    }

    func start() {
        geometry = currentGeometry()
        visualSize = geometry.collapsedSize
        let panel = NotchPanel()
        let root = NotchRootView()
            .environment(self)
            .environment(AppModel.shared.store)
            .environment(AppModel.shared.settings)
            .environment(AppModel.shared.nowPlaying)
            .environment(AppModel.shared.liveActivity)
        let hosting = SilentHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.shouldAcceptHit = { [weak hosting, weak self] point in
            guard let hosting, let self else { return false }
            let rect = self.geometry.visualFrame(
                in: hosting.bounds,
                size: self.visualSize
            ).insetBy(dx: -2, dy: -2)
            return rect.contains(point)
        }
        panel.embed(hosting: hosting)
        self.panel = panel
        self.hostingView = hosting
        panel.setFrameImmediately(collapsedPanelFrame)
        panel.applyOverlayPolicy(showInSystemSurfaces: AppModel.shared.settings.showInSystemSurfaces)
        panel.orderFrontRegardless()

        visibility = NotchVisibility(
            panel: panel,
            displayID: { [weak self] in
                self?.geometry.displayID ?? 0
            },
            keepVisible: {
                AccessoryWindowPolicy.hasVisibleWindows
            }
        )
        visibility?.start()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reposition(animated: false)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.clickedOutside()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleLocalMouseDown(event)
            return event
        }
        globalHoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.updateHoverFromMouseLocation()
            }
        }
        localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { [weak self] event in
            self?.updateHoverFromMouseLocation()
            return event
        }
        updateHoverFromMouseLocation()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalHoverMonitor {
            NSEvent.removeMonitor(globalHoverMonitor)
            self.globalHoverMonitor = nil
        }
        if let localHoverMonitor {
            NSEvent.removeMonitor(localHoverMonitor)
            self.localHoverMonitor = nil
        }
        collapseWindowWorkItem?.cancel()
        visibility?.stop()
        visibility = nil
        panel?.close()
        panel = nil
        hostingView = nil
    }

    func requestSearchFocus() {
        if !isExpanded {
            expand(pinned: true)
        } else if !isPinned {
            isPinned = true
        }
        focusSearchField()
    }

    func visibilityRefresh() {
        visibility?.refresh()
    }

    func applyOverlayPolicy() {
        panel?.applyOverlayPolicy(showInSystemSurfaces: AppModel.shared.settings.showInSystemSurfaces)
        visibility?.refresh()
    }

    func applyLayoutStyle() {
        collapseWindowWorkItem?.cancel()
        isHoverPeeking = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            geometry = currentGeometry()
            layoutGeneration += 1
            setWindowToCurrentState()
        }
        updateHoverFromMouseLocation()
    }

    func applyOpenOnHover() {
        if AppModel.shared.settings.openOnHover {
            isHoverPeeking = false
        }
        guard !isExpanded else { return }
        setWindowToCurrentState()
        updateHoverFromMouseLocation()
    }

    func applyClipboardEnabled() {
        geometry = currentGeometry()
        if isExpanded {
            setWindowToCurrentState()
        }
    }

    private func currentGeometry(mouseScreenForHotkey: Bool = false) -> NotchGeometry {
        .current(
            style: AppModel.shared.settings.layoutStyle,
            mouseScreenForHotkey: mouseScreenForHotkey,
            clipboardEnabled: AppModel.shared.settings.clipboardEnabled
        )
    }

    func mouseEntered() {
        isMouseInHoverTarget = true
        cancelCollapse()
        guard !suppressHoverExpand else { return }
        guard !AccessoryWindowPolicy.hasVisibleWindows else { return }
        if AppModel.shared.settings.openOnHover {
            if !isExpanded {
                expand(pinned: false)
            }
        } else {
            applyHoverPeek(true)
        }
    }

    func mouseExited() {
        guard !hoverFrameContainsMouse() else {
            isMouseInHoverTarget = true
            return
        }
        isMouseInHoverTarget = false
        suppressHoverExpand = false
        applyHoverPeek(false)
        guard isExpanded, !isPinned, !isDraggingClip else { return }
        scheduleCollapse()
    }

    private func hoverFrameContainsMouse() -> Bool {
        guard let panel, panel.isVisible else { return false }
        let frame = geometry.hoverScreenFrame(
            visualSize: visualSize,
            panelFrame: panel.frame,
            expanded: isExpanded || panelFrameIsExpanded
        )
        return frame.contains(NSEvent.mouseLocation)
    }

    private func updateHoverFromMouseLocation() {
        let over = hoverFrameContainsMouse()
        guard over != isMouseInHoverTarget else { return }
        if over {
            mouseEntered()
        } else {
            mouseExited()
        }
    }

    func clickedNotch() {
        if isPinned {
            collapse()
        } else {
            expand(pinned: true)
        }
    }

    func toggleFromHotkey() {
        geometry = currentGeometry(mouseScreenForHotkey: true)
        if isPinned && isExpanded {
            collapse()
        } else {
            expand(pinned: true)
        }
    }

    func expand(pinned: Bool) {
        cancelCollapse()
        rememberFrontmostApp()
        isPinned = pinned
        isHoverPeeking = false
        panel?.hasShadow = false
        panel?.setAcceptsKeyboard(true)
        panel?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
        // Jump the window to the expanded rect with no animation. WindowServer
        // otherwise scales the panel from its center (the notch drops, then zooms).
        panel?.setFrameImmediately(geometry.expandedPanelFrame)
        panelFrameIsExpanded = true
        isExpanded = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isExpanded else { return }
            self.visualSize = self.geometry.expandedSize
        }
        if AppModel.shared.settings.clipboardEnabled {
            focusSearchField()
        }
    }

    func pinOpen() {
        guard isExpanded else { return }
        isPinned = true
        cancelCollapse()
    }

    func collapse(restoreApp: Bool = true) {
        isDraggingClip = false
        draggingSource = nil
        cancelCollapse()
        isPinned = false
        isExpanded = false
        isHoverPeeking = false
        panel?.hasShadow = false
        panel?.setAcceptsKeyboard(false)
        AppModel.shared.store.searchQuery = ""
        visualSize = geometry.collapsedSize
        scheduleWindowShrink()
        if restoreApp, !AccessoryWindowPolicy.hasVisibleWindows {
            previousApp?.activate()
        }
    }

    func pasteItem(_ item: ClipItem, plainText: Bool) {
        let app = previousApp
        suppressHoverExpand = true
        collapse(restoreApp: false)
        panel?.setAcceptsKeyboard(false)
        PasteService.paste(item, plainText: plainText, into: app)
    }

    func openSettings() {
        suppressHoverExpand = true
        collapse(restoreApp: false)
        panel?.setAcceptsKeyboard(false)
        SettingsWindowController.shared.show()
    }

    func openAbout() {
        suppressHoverExpand = true
        collapse(restoreApp: false)
        panel?.setAcceptsKeyboard(false)
        AboutWindowController.shared.show()
    }

    func startDragging(_ item: ClipItem) {
        guard !isDraggingClip else { return }
        guard let hostingView, let event = NSApp.currentEvent else { return }
        let writers = item.draggingWriters()
        guard !writers.isEmpty else { return }

        isDraggingClip = true
        cancelCollapse()

        let preview = item.dragPreviewImage()
        let maxPreview = NSSize(width: 148, height: 96)
        let scale = min(1, min(maxPreview.width / max(preview.size.width, 1), maxPreview.height / max(preview.size.height, 1)))
        let previewSize = NSSize(
            width: max(48, preview.size.width * scale),
            height: max(32, preview.size.height * scale)
        )
        let location = hostingView.convert(event.locationInWindow, from: nil)
        let origin = NSPoint(x: location.x - previewSize.width / 2, y: location.y - previewSize.height / 2)

        let source = ClipDraggingSource { [weak self] in
            self?.endClipDrag()
        }
        draggingSource = source

        let dragItems = writers.enumerated().map { index, writer -> NSDraggingItem in
            let dragItem = NSDraggingItem(pasteboardWriter: writer)
            if index == 0 {
                dragItem.setDraggingFrame(NSRect(origin: origin, size: previewSize), contents: preview)
            } else {
                dragItem.setDraggingFrame(NSRect(origin: origin, size: .zero), contents: nil)
            }
            return dragItem
        }

        let session = hostingView.beginDraggingSession(with: dragItems, event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func endClipDrag() {
        guard isDraggingClip else { return }
        isDraggingClip = false
        draggingSource = nil
        if !isPinned {
            let overPanel = panel.map { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? false
            if !overPanel {
                scheduleCollapse()
            }
        }
    }

    private func rememberFrontmostApp() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
    }

    private var collapsedPanelFrame: CGRect {
        geometry.collapsedWindowFrame(hoverPeekReserved: !AppModel.shared.settings.openOnHover)
    }

    private func applyHoverPeek(_ on: Bool) {
        guard !isExpanded else { return }
        guard !AppModel.shared.settings.openOnHover else { return }
        guard isHoverPeeking != on else { return }
        isHoverPeeking = on
        visualSize = geometry.collapsedSize(peeking: on)
    }

    private func setWindowToCurrentState() {
        if isExpanded {
            panel?.setFrameImmediately(geometry.expandedPanelFrame)
            panelFrameIsExpanded = true
            visualSize = geometry.expandedSize
        } else {
            panel?.setFrameImmediately(collapsedPanelFrame)
            panelFrameIsExpanded = false
            visualSize = geometry.collapsedSize(peeking: isHoverPeeking)
        }
    }

    private func scheduleWindowShrink() {
        collapseWindowWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.panelFrameIsExpanded = false
            if !AppModel.shared.settings.openOnHover,
               let panel = self.panel,
               panel.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) {
                self.applyHoverPeek(true)
            } else {
                self.visualSize = self.geometry.collapsedSize
                self.panel?.setFrameImmediately(self.collapsedPanelFrame)
            }
            self.panel?.setAcceptsKeyboard(false)
            AccessoryWindowPolicy.restoreKeyWindow()
        }
        collapseWindowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
    }

    private func reposition(animated: Bool) {
        geometry = currentGeometry()
        setWindowToCurrentState()
    }

    private func scheduleCollapse() {
        cancelCollapse()
        let work = DispatchWorkItem { [weak self] in
            self?.collapse()
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func cancelCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        collapseWindowWorkItem?.cancel()
        collapseWindowWorkItem = nil
    }

    private func clickedOutside() {
        guard isExpanded, !isDraggingClip else { return }
        collapse()
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard event.window == panel else { return }
        if !isExpanded {
            clickedNotch()
        } else if !isPinned {
            expand(pinned: true)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isExpanded else { return event }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command), event.charactersIgnoringModifiers == "," {
            openSettings()
            return nil
        }

        let clipboardEnabled = AppModel.shared.settings.clipboardEnabled

        if event.keyCode == 53 { // escape
            if clipboardEnabled, !AppModel.shared.store.searchQuery.isEmpty {
                AppModel.shared.store.searchQuery = ""
                return nil
            }
            collapse()
            return nil
        }

        if clipboardEnabled, flags.contains(.command), event.charactersIgnoringModifiers == "f" {
            requestSearchFocus()
            return nil
        }

        if clipboardEnabled, flags.contains(.command), let number = commandNumber(from: event) {
            let items = AppModel.shared.store.filteredItems
            let index = number - 1
            if items.indices.contains(index) {
                pasteItem(items[index], plainText: flags.contains(.shift))
            }
            return nil
        }

        if clipboardEnabled, AppModel.shared.settings.plainPasteShortcut.matches(event) {
            if let selected = AppModel.shared.store.selectedItem {
                pasteItem(selected, plainText: true)
            }
            return nil
        }

        if clipboardEnabled, event.keyCode == 36 || event.keyCode == 76 { // return
            if let selected = AppModel.shared.store.selectedItem {
                pasteItem(selected, plainText: false)
                return nil
            }
        }

        // Arrows move the card selection; the previous app is restored only on paste/escape.
        if clipboardEnabled, event.keyCode == 123 || event.keyCode == 126 { // left, up
            AppModel.shared.store.selectPrevious()
            return nil
        }
        if clipboardEnabled, event.keyCode == 124 || event.keyCode == 125 { // right, down
            AppModel.shared.store.selectNext()
            return nil
        }

        let fieldIsEditing = panel?.firstResponder is NSTextView

        if clipboardEnabled, event.keyCode == 51 { // delete
            if fieldIsEditing { return event }
            var query = AppModel.shared.store.searchQuery
            if !query.isEmpty {
                query.removeLast()
                AppModel.shared.store.searchQuery = query
                return nil
            }
        }

        if clipboardEnabled, let text = searchInsertText(from: event) {
            pinOpen()
            if fieldIsEditing { return event }
            AppModel.shared.store.searchQuery += text
            focusSearchField()
            return nil
        }

        return event
    }

    private func focusSearchField() {
        searchFocusGeneration += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard isExpanded, let panel else { return }
            panel.makeKey()
            if let hostingView, let field = Self.firstTextField(in: hostingView) {
                panel.makeFirstResponder(field)
            } else {
                panel.makeFirstResponder(hostingView)
            }
        }
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField {
            return field
        }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) {
                return field
            }
        }
        return nil
    }

    private func searchInsertText(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) { return nil }
        switch event.keyCode {
        case 36, 48, 53, 76, 123, 124, 125, 126, 51, 117:
            return nil
        default:
            break
        }
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        let filtered = characters.filter { !$0.isNewline && $0 != "\u{1b}" }
        return filtered.isEmpty ? nil : String(filtered)
    }

    private func commandNumber(from event: NSEvent) -> Int? {
        if let chars = event.charactersIgnoringModifiers, let number = Int(chars), (1...9).contains(number) {
            return number
        }
        let ansi: [UInt16: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
        ]
        return ansi[event.keyCode]
    }
}

private final class ClipDraggingSource: NSObject, NSDraggingSource {
    let onEnd: () -> Void

    init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DispatchQueue.main.async { [onEnd] in
            onEnd()
        }
    }
}

struct NotchRootView: View {
    @Environment(NotchHost.self) private var host
    @Environment(ClipboardStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NotchView()
            .id(host.layoutGeneration)
            .environment(host)
            .environment(store)
            .environment(settings)
            .environment(AppModel.shared.nowPlaying)
            .environment(AppModel.shared.liveActivity)
    }
}
