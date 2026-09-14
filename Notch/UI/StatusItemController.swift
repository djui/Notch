import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private weak var host: NotchHost?
    private var settings: AppSettings?

    func install(host: NotchHost, settings: AppSettings) {
        self.host = host
        self.settings = settings
        applyVisibility()
    }

    func applyVisibility() {
        let visible = settings?.showStatusItem ?? true
        if visible {
            if item == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.image = MenuBarIcon.image()
                    button.imagePosition = .imageOnly
                    button.toolTip = "Notch"
                }
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
                self.item = item
            }
            item?.isVisible = true
        } else {
            item?.isVisible = false
        }
    }

    func refreshMenu() {
        if let menu = item?.menu {
            menuNeedsUpdate(menu)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcut = settings?.openShortcut ?? .defaultOpen
        let open = menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: shortcut.menuKeyEquivalent)
        open.keyEquivalentModifierMask = shortcut.nsEventModifiers
        open.target = self

        let paused = settings?.isPaused == true
        let pause = menu.addItem(
            withTitle: paused ? "Resume Capture" : "Pause Capture",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self

        let plainShortcut = settings?.plainPasteShortcut ?? .defaultPlainPaste
        if plainShortcut.isValidGlobal, !plainShortcut.menuKeyEquivalent.isEmpty {
            let plain = menu.addItem(
                withTitle: "Paste as Plain Text",
                action: #selector(pastePlain),
                keyEquivalent: plainShortcut.menuKeyEquivalent
            )
            plain.keyEquivalentModifierMask = plainShortcut.nsEventModifiers
            plain.target = self
        }

        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let hide = menu.addItem(withTitle: "Hide Menu Bar Icon", action: #selector(hideStatusItem), keyEquivalent: "")
        hide.target = self

        menu.addItem(.separator())
        let about = menu.addItem(withTitle: "About Notch", action: #selector(openAbout), keyEquivalent: "")
        about.target = self

        let relaunch = menu.addItem(withTitle: "Relaunch Notch", action: #selector(relaunch), keyEquivalent: "r")
        relaunch.target = self

        let quit = menu.addItem(withTitle: "Quit Notch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
    }

    @objc private func openNotch() {
        host?.toggleFromHotkey()
    }

    @objc private func pastePlain() {
        AppModel.shared.pasteSelectedAsPlainText()
    }

    @objc private func togglePause() {
        settings?.isPaused.toggle()
    }

    @objc private func openSettings() {
        host?.openSettings()
    }

    @objc private func openAbout() {
        host?.openAbout()
    }

    @objc private func hideStatusItem() {
        settings?.showStatusItem = false
    }

    @objc private func relaunch() {
        NSApp.relaunch()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
