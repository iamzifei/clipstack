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
    private let onboarding = OnboardingWindowController()

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
        hotKeys.ringOwnsSwitcherCombo = { [weak self] in self?.ringSharesPanelCombo ?? false }
        settings.model.onHotKeysChanged = { [weak self] in
            self?.ring.reloadCombo()
            self?.hotKeys.reload()
        }
        settings.model.suspendHotKeys = { [weak self] in self?.hotKeys.suspend() }

        // Opt-in hold-and-tap ring (default hold ⇧⌘, tap V). Dormant (no
        // event tap, no permission request) unless enabled in Settings.
        ring.canBegin = { [weak self] in
            guard let self else { return .pass }
            // While Settings records a shortcut, every key must reach it.
            if self.settings.model.recordingTarget != nil { return .pass }
            // Never start a ring inside ClipStack's own windows (settings,
            // the panel's search field) or with nothing to cycle through.
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let canRing = !self.store.items.isEmpty
                && !self.switcher.hasKeyFocus
                && front != ProcessInfo.processInfo.processIdentifier
            if canRing { return .ring }
            // Shared with the panel shortcut: behave exactly like it.
            return self.ringSharesPanelCombo ? .panel : .pass
        }
        ring.handler = { [weak self] event, immediate in
            guard let self else { return }
            switch event {
            case .begin: self.switcher.ringBegin()
            case .step(let delta): self.switcher.ringStep(delta)
            case .delete: self.switcher.ringDelete()
            case .cancel: self.switcher.ringCancel()
            case .commit:
                // A single press of a combo shared with the panel opens the
                // panel (no paste); otherwise it pastes like ⌘V always did.
                self.switcher.ringCommit(immediate: immediate, untouchedOpensPanel: self.ringSharesPanelCombo)
            case .panel: self.switcher.toggle()
            }
        }
        ring.onInstalledChange = { [weak self] in
            // Mid-recording the hotkeys stay suspended; endRecording reloads.
            guard let self, self.settings.model.recordingTarget == nil else { return }
            self.hotKeys.reload()
        }
        settings.model.onPasteOptionsChanged = { [weak self] in self?.applyRingSetting() }
        hotKeys.reload()
        applyRingSetting()

        // First-run welcome guide (also shown once to people upgrading from
        // a version without it). Reopenable from the menu-bar menu.
        onboarding.onOpenPanel = { [weak self] in self?.switcher.show() }
        statusMenu.onShowGuide = { [weak self] in self?.onboarding.show() }
        onboarding.showIfNeeded()
    }

    /// The ring is live and uses the same combo as the panel shortcut.
    private var ringSharesPanelCombo: Bool {
        ring.isInstalled && CmdVRing.combo == HotKeys.switcherCombo
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
