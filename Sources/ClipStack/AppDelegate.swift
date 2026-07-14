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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: a second launch just quits itself.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

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
        settings = SettingsWindowController()
        statusMenu = StatusMenuController(
            store: store,
            monitor: monitor,
            switcher: switcher,
            settings: settings,
            toast: toast
        )
        store.onChange = { [weak self] in self?.switcher.refreshIfVisible() }
        monitor.start()

        // Global hotkeys (⇧⌘V switcher, ⌘. settings by default) — rebindable
        // from the settings window, stored in UserDefaults.
        hotKeys = HotKeys()
        hotKeys.openSwitcher = { [weak self] in self?.switcher.toggle() }
        hotKeys.openSettings = { [weak self] in self?.settings.show() }
        settings.model.onHotKeysChanged = { [weak self] in self?.hotKeys.reload() }
        settings.model.suspendHotKeys = { [weak self] in self?.hotKeys.suspend() }
        hotKeys.reload()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.save()
    }
}
