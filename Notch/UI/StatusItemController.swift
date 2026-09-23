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
        let open = menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "")
        open.target = self

        menu.addItem(.separator())
        let layoutMenu = NSMenu()
        for style in NotchLayoutStyle.allCases {
            let item = layoutMenu.addItem(
                withTitle: style.title,
                action: #selector(selectLayout(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.rawValue
            item.state = settings?.layoutStyle == style ? .on : .off
        }
        let layoutItem = menu.addItem(withTitle: "Layout", action: nil, keyEquivalent: "")
        menu.setSubmenu(layoutMenu, for: layoutItem)

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

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = NotchLayoutStyle(rawValue: raw) else { return }
        settings?.layoutStyle = style
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
