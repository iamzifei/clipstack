import AppKit
import ServiceManagement
import ClipStackCore

/// The menu-bar icon and its dropdown: recent entries, pause, clear,
/// launch-at-login toggle and quit.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let switcher: SwitcherWindowController
    private let menu = NSMenu()

    init(store: HistoryStore, monitor: ClipboardMonitor, switcher: SwitcherWindowController) {
        self.store = store
        self.monitor = monitor
        self.switcher = switcher
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipStack")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ClipStack — ⇧⌘V 打开历史面板"
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "打开历史面板", action: #selector(openSwitcher), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let recent = Array(store.items.prefix(10))
        if recent.isEmpty {
            let empty = NSMenuItem(title: "（历史为空）", action: nil, keyEquivalent: "")
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
            title: monitor.isPaused ? "恢复监控" : "暂停监控",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        let clear = NSMenuItem(title: "清空历史（保留置顶）…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "开机自动启动", action: nil, keyEquivalent: "")
        if Bundle.main.bundleIdentifier != nil {
            login.action = #selector(toggleLaunchAtLogin)
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            login.title = "开机自动启动（需以 .app 运行）"
        }
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ClipStack", action: #selector(quit), keyEquivalent: "q")
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

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let item = store.items.first(where: { $0.id == id }) else { return }
        PasteboardWriter.write(item, store: store)
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "将删除所有未置顶的记录，置顶记录保留。此操作不可撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear(keepPinned: true)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "设置开机自启失败"
            alert.informativeText = "\(error.localizedDescription)\n\n可手动添加：系统设置 → 通用 → 登录项 → 添加 ClipStack.app"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
