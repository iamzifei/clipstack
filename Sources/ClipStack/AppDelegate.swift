import AppKit
import ClipStackCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var switcher: SwitcherWindowController!
    private var statusMenu: StatusMenuController!
    private var settings: SettingsWindowController!
    private var toast: ToastController!
    private var hotKeys: HotKeys!
    private var updater: Updater!
    private let ring = CmdVRing()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: a second launch just quits itself.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

        // Before any window exists, so nothing flashes in the wrong appearance.
        Appearance.apply(Appearance.stored)

        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipStack", isDirectory: true)
        let maxItems = UserDefaults.standard.object(forKey: PrefKey.maxItems) as? Int ?? 300
        do {
            store = try HistoryStore(directory: supportDir, maxItems: maxItems)
        } catch {
            NSLog("ClipStack: cannot create history store at \(supportDir.path): \(error)")
            NSApp.terminate(nil)
            return
        }

        toast = ToastController()
        monitor = ClipboardMonitor(store: store)
        switcher = SwitcherWindowController(store: store)
        switcher.onCopied = { [weak self] item in
            self?.toast.showCopied(detail: String(item.previewLine.prefix(48)))
        }
        switcher.onNotice = { [weak self] message in
            self?.toast.show(title: message, detail: nil)
        }
        settings = SettingsWindowController()
        // Sparkle auto-updater: starts background checks against the appcast
        // feed configured in Info.plist. No-op when running unbundled.
        updater = Updater()
        statusMenu = StatusMenuController(
            store: store,
            monitor: monitor,
            switcher: switcher,
            settings: settings,
            toast: toast,
            updater: updater
        )
        store.onChange = { [weak self] in self?.switcher.refreshIfVisible() }
        monitor.start()

        // Global hotkeys (⇧⌘V switcher, ⌘, settings, ⇧⌘⌫ clear-all by
        // default) — rebindable from the settings window, stored in UserDefaults.
        hotKeys = HotKeys()
        hotKeys.openSwitcher = { [weak self] in self?.switcher.toggle() }
        hotKeys.openSettings = { [weak self] in self?.settings.show() }
        hotKeys.clearAll = { [weak self] in self?.statusMenu.confirmAndClearAll() }
        settings.model.onHotKeysChanged = { [weak self] in self?.hotKeys.reload() }
        settings.model.suspendHotKeys = { [weak self] in self?.hotKeys.suspend() }
        hotKeys.reload()

        // Opt-in hold-⌘-tap-V ring. Dormant (no event tap, no permission
        // request) unless the user enabled it in Settings.
        ring.canBegin = { [weak self] in
            guard let self else { return false }
            // Never hijack ⌘V inside ClipStack's own windows (settings,
            // the panel's search field): there it must paste normally.
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            return !self.store.items.isEmpty
                && !self.switcher.hasKeyFocus
                && front != ProcessInfo.processInfo.processIdentifier
        }
        ring.handler = { [weak self] event, immediate in
            guard let switcher = self?.switcher else { return }
            switch event {
            case .begin: switcher.ringBegin()
            case .step(let delta): switcher.ringStep(delta)
            case .delete: switcher.ringDelete()
            case .cancel: switcher.ringCancel()
            case .commit: switcher.ringCommit(immediate: immediate)
            }
        }
        settings.model.onPasteOptionsChanged = { [weak self] in self?.applyRingSetting() }
        applyRingSetting()
    }

    private func applyRingSetting() {
        if UserDefaults.standard.bool(forKey: PrefKey.cmdVRing) {
            ring.enable()
        } else {
            ring.disable()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.save()
    }
}
