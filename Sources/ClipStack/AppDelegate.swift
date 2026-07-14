import AppKit
import Carbon.HIToolbox
import ClipStackCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var switcher: SwitcherWindowController!
    private var statusMenu: StatusMenuController!

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
        let maxItems = UserDefaults.standard.object(forKey: "MaxItems") as? Int ?? 300
        do {
            store = try HistoryStore(directory: supportDir, maxItems: maxItems)
        } catch {
            NSLog("ClipStack: cannot create history store at \(supportDir.path): \(error)")
            NSApp.terminate(nil)
            return
        }

        monitor = ClipboardMonitor(store: store)
        switcher = SwitcherWindowController(store: store)
        statusMenu = StatusMenuController(store: store, monitor: monitor, switcher: switcher)
        store.onChange = { [weak self] in self?.switcher.refreshIfVisible() }
        monitor.start()

        // Global hotkey, default ⇧⌘V. Overridable without a prefs UI:
        //   defaults write com.james.ClipStack HotKeyKeyCode -int <keycode>
        //   defaults write com.james.ClipStack HotKeyModifiers -int <carbon flags>
        let keyCode = UInt32(UserDefaults.standard.object(forKey: "HotKeyKeyCode") as? Int ?? kVK_ANSI_V)
        let modifiers = UInt32(UserDefaults.standard.object(forKey: "HotKeyModifiers") as? Int ?? (cmdKey | shiftKey))
        let registered = HotKeyCenter.shared.register(keyCode: keyCode, carbonModifiers: modifiers) { [weak self] in
            self?.switcher.toggle()
        }
        if !registered {
            NSLog("ClipStack: global hotkey registration failed (conflict?). Panel is still reachable from the menu bar icon.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.save()
    }
}
