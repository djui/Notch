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
    private var visibility: NotchVisibility?
    private let morphAnimator = NotchMorphAnimator()
    private var workspaceObservers: [NSObjectProtocol] = []

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
            .environment(AppModel.shared.settings)
            .environment(AppModel.shared.nowPlaying)
            .environment(AppModel.shared.liveActivity)
        let hosting = SilentHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.shouldAcceptHit = { [weak hosting, weak self] point in
            guard let hosting, let self else { return false }
            let visual = self.geometry.visualFrame(
                in: hosting.bounds,
                size: self.visualSize
            )
            let hit = CGRect(
                x: visual.minX,
                y: visual.minY,
                width: visual.width,
                height: max(visual.height, hosting.bounds.maxY - visual.minY)
            ).insetBy(dx: -2, dy: -2)
            return hit.contains(point)
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

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDisplayWake()
                }
            }
            workspaceObservers.append(observer)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleGlobalMouseDown()
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
        morphAnimator.stop()
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
        workspaceObservers.removeAll()
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
        collapseWorkItem?.cancel()
        visibility?.stop()
        visibility = nil
        panel?.close()
        panel = nil
        hostingView = nil
    }

    func visibilityRefresh() {
        visibility?.refresh()
    }

    func applyOverlayPolicy() {
        panel?.applyOverlayPolicy(showInSystemSurfaces: AppModel.shared.settings.showInSystemSurfaces)
        visibility?.refresh()
    }

    func applyLayoutStyle() {
        morphAnimator.stop()
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

    private func currentGeometry(mouseScreenForHotkey: Bool = false) -> NotchGeometry {
        .current(
            style: AppModel.shared.settings.layoutStyle,
            mouseScreenForHotkey: mouseScreenForHotkey
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
        guard isExpanded, !isPinned else { return }
        scheduleCollapse()
    }

    private func hoverFrameContainsMouse() -> Bool {
        guard let panel, panel.isVisible else { return false }
        let frame = geometry.hoverScreenFrame(
            visualSize: visualSize,
            panelFrame: panel.frame,
            expanded: isExpanded || panelFrameIsExpanded
        )
        return geometry.containsMouse(NSEvent.mouseLocation, in: frame)
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
        animateVisualSize(to: geometry.expandedSize, curve: .expand)
    }

    func collapse(restoreApp: Bool = true) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        isPinned = false
        isExpanded = false
        isHoverPeeking = false
        panel?.hasShadow = false
        panel?.setAcceptsKeyboard(false)
        animateVisualSize(to: geometry.collapsedSize, curve: .easeOut) { [weak self] in
            self?.finishWindowShrink()
        }
        if restoreApp, !AccessoryWindowPolicy.hasVisibleWindows {
            previousApp?.activate()
        }
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

    func openNowPlayingSource() {
        let item = AppModel.shared.nowPlaying.item
        guard item != nil else { return }
        suppressHoverExpand = true
        collapse(restoreApp: false)
        panel?.setAcceptsKeyboard(false)
        NowPlayingSource.reveal(item)
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
        animateVisualSize(to: geometry.collapsedSize(peeking: on), curve: .easeOut)
    }

    private func setWindowToCurrentState() {
        morphAnimator.stop()
        if isExpanded {
            panel?.setFrameImmediately(geometry.expandedPanelFrame)
            panelFrameIsExpanded = true
            applyVisualSize(geometry.expandedSize)
        } else {
            panel?.setFrameImmediately(collapsedPanelFrame)
            panelFrameIsExpanded = false
            applyVisualSize(geometry.collapsedSize(peeking: isHoverPeeking))
        }
    }

    private func finishWindowShrink() {
        guard !isExpanded else { return }
        panelFrameIsExpanded = false
        if !AppModel.shared.settings.openOnHover,
           let panel = self.panel,
           panel.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) {
            applyHoverPeek(true)
        } else {
            applyVisualSize(geometry.collapsedSize)
            panel?.setFrameImmediately(collapsedPanelFrame)
        }
        panel?.setAcceptsKeyboard(false)
        AccessoryWindowPolicy.restoreKeyWindow()
    }

    private func reposition(animated: Bool) {
        morphAnimator.stop()
        geometry = currentGeometry()
        setWindowToCurrentState()
    }

    private func handleDisplayWake() {
        morphAnimator.stop()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            layoutGeneration += 1
            geometry = currentGeometry()
            setWindowToCurrentState()
        }
    }

    private func applyVisualSize(_ size: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visualSize = size
        }
    }

    private func animateVisualSize(
        to size: CGSize,
        curve: NotchMorphAnimator.Curve,
        onComplete: (() -> Void)? = nil
    ) {
        morphAnimator.animate(
            from: visualSize,
            to: size,
            curve: curve,
            window: panel,
            onTick: { [weak self] next in
                self?.applyVisualSize(next)
            },
            onComplete: onComplete
        )
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
    }

    private func clickedOutside() {
        guard isExpanded else { return }
        collapse()
    }

    /// Clicks that miss the panel (top screen edge, island menu-bar gap) never
    /// become local events. Treat those as overlay clicks when collapsed.
    private func handleGlobalMouseDown() {
        if hoverFrameContainsMouse() {
            if !isExpanded {
                clickedNotch()
            }
            return
        }
        clickedOutside()
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

        if event.keyCode == 53 { // escape
            collapse()
            return nil
        }

        return event
    }
}

struct NotchRootView: View {
    @Environment(NotchHost.self) private var host
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NotchView()
            .id(host.layoutGeneration)
            .environment(host)
            .environment(settings)
            .environment(AppModel.shared.nowPlaying)
            .environment(AppModel.shared.liveActivity)
    }
}
