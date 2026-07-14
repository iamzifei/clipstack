import AppKit
import ClipStackCore

/// The menu-bar icon and its dropdown: recent entries, settings, pause,
/// clear and quit. The button image is a template TIFF (18pt @1x/@2x) so
/// macOS recolors it automatically for light/dark menu bars.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let switcher: SwitcherWindowController
    private let settings: SettingsWindowController
    private let toast: ToastController
    private let menu = NSMenu()

    init(
        store: HistoryStore,
        monitor: ClipboardMonitor,
        switcher: SwitcherWindowController,
        settings: SettingsWindowController,
        toast: ToastController
    ) {
        self.store = store
        self.monitor = monitor
        self.switcher = switcher
        self.settings = settings
        self.toast = toast
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.menuBarImage()
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    /// v1.0-style SF Symbol glyph. Template image, so macOS recolors it
    /// automatically for light/dark menu bars and the highlighted state.
    private static func menuBarImage() -> NSImage? {
        let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipStack")
        symbol?.isTemplate = true
        return symbol
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let switcherCombo = HotKeys.switcherCombo
        statusItem.button?.toolTip = String(
            format: L("tooltip"),
            KeyMap.displayString(keyCode: switcherCombo.code, carbonModifiers: UInt32(switcherCombo.mods))
        )

        let open = NSMenuItem(
            title: L("menu_open_panel"),
            action: #selector(openSwitcher),
            keyEquivalent: KeyMap.keyEquivalentChar(forKeyCode: switcherCombo.code) ?? ""
        )
        open.keyEquivalentModifierMask = NSEvent.ModifierFlags(
            rawValue: KeyMap.cocoaFlags(fromCarbon: UInt32(switcherCombo.mods))
        )
        open.target = self
        menu.addItem(open)

        let settingsCombo = HotKeys.settingsCombo
        let prefs = NSMenuItem(
            title: L("menu_settings"),
            action: #selector(openSettings),
            keyEquivalent: KeyMap.keyEquivalentChar(forKeyCode: settingsCombo.code) ?? ""
        )
        prefs.keyEquivalentModifierMask = NSEvent.ModifierFlags(
            rawValue: KeyMap.cocoaFlags(fromCarbon: UInt32(settingsCombo.mods))
        )
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        let recent = Array(store.items.prefix(10))
        if recent.isEmpty {
            let empty = NSMenuItem(title: L("menu_empty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for item in recent {
            let menuItem = NSMenuItem(title: menuTitle(item), action: #selector(copyRecent(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.id.uuidString
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: monitor.isPaused ? L("menu_resume") : L("menu_pause"),
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        let clear = NSMenuItem(title: L("menu_clear"), action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("menu_quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func menuTitle(_ item: ClipItem) -> String {
        let pin = item.pinned ? "📌 " : ""
        switch item.kind {
        case .text: return pin + String(item.previewLine.prefix(50))
        case .image: return pin + "🖼 " + item.previewLine
        case .file: return pin + "📄 " + String(item.previewLine.prefix(50))
        }
    }

    // MARK: actions

    @objc private func openSwitcher() {
        switcher.show()
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let item = store.items.first(where: { $0.id == id }) else { return }
        PasteboardWriter.write(item, store: store)
        toast.showCopied(detail: String(item.previewLine.prefix(48)))
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("alert_clear_title")
        alert.informativeText = L("alert_clear_msg")
        alert.addButton(withTitle: L("alert_clear_ok"))
        alert.addButton(withTitle: L("alert_cancel"))
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear(keepPinned: true)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
