import AppKit
import SwiftUI
import ServiceManagement
import ClipStackCore

/// Applies the light / dark / system choice to every ClipStack window,
/// menu and panel at once. `nil` lets AppKit follow the system setting.
enum Appearance {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static var stored: AppearanceMode {
        AppearanceMode(stored: UserDefaults.standard.string(forKey: PrefKey.appearance))
    }
}

/// Backing model for the settings window: launch-at-login toggle plus a
/// click-to-record editor for the two global hotkeys.
final class SettingsModel: ObservableObject {
    enum Target { case switcher, settings, clearAll }

    @Published var switcherCode: Int
    @Published var switcherMods: Int
    @Published var settingsCode: Int
    @Published var settingsMods: Int
    @Published var clearAllCode: Int
    @Published var clearAllMods: Int
    @Published var launchAtLogin = false
    @Published var loginError: String?
    @Published var recordingTarget: Target?
    @Published var recordHint: String?
    /// Opt-in paste automation (both need the Accessibility permission).
    @Published var autoPaste = UserDefaults.standard.bool(forKey: PrefKey.autoPaste)
    @Published var cmdVRing = UserDefaults.standard.bool(forKey: PrefKey.cmdVRing)
    @Published var accessibilityGranted = Accessibility.isTrusted()
    @Published var appearance = Appearance.stored
    /// "system" or an AppLanguage code (same setting as the guide's picker).
    @Published var language = AppLanguage.storedChoice ?? "system"

    var onHotKeysChanged: () -> Void = {}
    var onPasteOptionsChanged: () -> Void = {}
    var suspendHotKeys: () -> Void = {}
    private var monitor: Any?

    init() {
        let switcher = HotKeys.switcherCombo
        let settings = HotKeys.settingsCombo
        let clearAll = HotKeys.clearAllCombo
        switcherCode = switcher.code
        switcherMods = switcher.mods
        settingsCode = settings.code
        settingsMods = settings.mods
        clearAllCode = clearAll.code
        clearAllMods = clearAll.mods
        refreshLoginState()
    }

    var canToggleLogin: Bool { Bundle.main.bundleIdentifier != nil }

    func setLanguage(_ choice: String) {
        language = choice
        AppLanguage.storedChoice = choice == "system" ? nil : choice
    }

    func setAppearance(_ mode: AppearanceMode) {
        appearance = mode
        UserDefaults.standard.set(mode.rawValue, forKey: PrefKey.appearance)
        Appearance.apply(mode)
    }

    func setAutoPaste(_ on: Bool) {
        autoPaste = on
        UserDefaults.standard.set(on, forKey: PrefKey.autoPaste)
        if on { requestAccessibility() }
        onPasteOptionsChanged()
    }

    func setCmdVRing(_ on: Bool) {
        cmdVRing = on
        UserDefaults.standard.set(on, forKey: PrefKey.cmdVRing)
        if on { requestAccessibility() }
        onPasteOptionsChanged()
    }

    /// Shows macOS's own "allow Accessibility" prompt the first time; the
    /// state line in the window re-checks whenever the window is shown.
    private func requestAccessibility() {
        accessibilityGranted = Accessibility.isTrusted(prompt: true)
    }

    func refreshAccessibility() {
        // Polled every second while Settings is open: only publish changes,
        // so the form doesn't re-render needlessly.
        let trusted = Accessibility.isTrusted()
        if trusted != accessibilityGranted { accessibilityGranted = trusted }
    }

    func refreshLoginState() {
        launchAtLogin = canToggleLogin && SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard canToggleLogin else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = String(format: L("login_error"), error.localizedDescription)
        }
        refreshLoginState()
    }

    func displayString(for target: Target) -> String {
        switch target {
        case .switcher:
            return KeyMap.displayString(keyCode: switcherCode, carbonModifiers: UInt32(switcherMods))
        case .settings:
            return KeyMap.displayString(keyCode: settingsCode, carbonModifiers: UInt32(settingsMods))
        case .clearAll:
            return KeyMap.displayString(keyCode: clearAllCode, carbonModifiers: UInt32(clearAllMods))
        }
    }

    // MARK: hotkey recording

    func beginRecording(_ target: Target) {
        guard monitor == nil else { return }
        recordingTarget = target
        recordHint = nil
        // Release current registrations so the bound combos reach the monitor.
        suspendHotKeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecorded(event)
            return nil // swallow while recording
        }
    }

    private func handleRecorded(_ event: NSEvent) {
        guard let target = recordingTarget else { return }
        if event.keyCode == 53 { // esc cancels
            endRecording()
            return
        }
        let raw = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let carbon = KeyMap.carbonFlags(fromCocoa: UInt(raw))
        guard KeyMap.hasRequiredModifier(carbon: carbon) else {
            recordHint = L("hk_need_mod")
            return
        }
        let code = Int(event.keyCode)
        let mods = Int(carbon)
        // Reject a combo already bound to either of the other two hotkeys.
        let others: [(Int, Int)]
        switch target {
        case .switcher: others = [(settingsCode, settingsMods), (clearAllCode, clearAllMods)]
        case .settings: others = [(switcherCode, switcherMods), (clearAllCode, clearAllMods)]
        case .clearAll: others = [(switcherCode, switcherMods), (settingsCode, settingsMods)]
        }
        guard !others.contains(where: { $0 == (code, mods) }) else {
            recordHint = L("hk_conflict")
            return
        }

        let defaults = UserDefaults.standard
        switch target {
        case .switcher:
            switcherCode = code
            switcherMods = mods
            defaults.set(code, forKey: PrefKey.hotKeyCode)
            defaults.set(mods, forKey: PrefKey.hotKeyMods)
        case .settings:
            settingsCode = code
            settingsMods = mods
            defaults.set(code, forKey: PrefKey.settingsHotKeyCode)
            defaults.set(mods, forKey: PrefKey.settingsHotKeyMods)
        case .clearAll:
            clearAllCode = code
            clearAllMods = mods
            defaults.set(code, forKey: PrefKey.clearAllHotKeyCode)
            defaults.set(mods, forKey: PrefKey.clearAllHotKeyMods)
        }
        endRecording()
    }

    /// Stops recording (with or without a captured combo) and re-registers.
    func endRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recordingTarget = nil
        recordHint = nil
        onHotKeysChanged()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(L("login_toggle"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .disabled(!model.canToggleLogin)
                if !model.canToggleLogin {
                    Text(L("login_requires_app"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Picker(L("appearance"), selection: Binding(
                    get: { model.appearance },
                    set: { model.setAppearance($0) }
                )) {
                    Text(L("appearance_system")).tag(AppearanceMode.system)
                    Text(L("appearance_light")).tag(AppearanceMode.light)
                    Text(L("appearance_dark")).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                Picker(L("language"), selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) }
                )) {
                    Text(String(format: L("language_system"), AppLanguage.nativeName(
                        AppLanguage.resolve(override: nil, preferred: Locale.preferredLanguages)))).tag("system")
                    Divider()
                    ForEach(AppLanguage.supported, id: \.self) { code in
                        Text(AppLanguage.nativeName(code)).tag(code)
                    }
                }
            }
            Section(L("hotkeys_section")) {
                recorderRow(L("hk_switcher"), .switcher)
                recorderRow(L("hk_settings"), .settings)
                recorderRow(L("hk_clear_all"), .clearAll)
                if let hint = model.recordHint {
                    Text(hint).font(.caption).foregroundStyle(.orange)
                }
                Text(L("hk_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("paste_section")) {
                Toggle(L("paste_auto"), isOn: Binding(
                    get: { model.autoPaste },
                    set: { model.setAutoPaste($0) }
                ))
                Toggle(L("paste_ring"), isOn: Binding(
                    get: { model.cmdVRing },
                    set: { model.setCmdVRing($0) }
                ))
                if model.autoPaste || model.cmdVRing {
                    HStack {
                        Image(systemName: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                        Text(L(model.accessibilityGranted ? "ax_granted" : "ax_missing"))
                            .font(.caption)
                        Spacer()
                        if !model.accessibilityGranted {
                            Button(L("ax_open")) { Accessibility.openSystemSettings() }
                                .controlSize(.small)
                        }
                    }
                    if !model.accessibilityGranted {
                        // macOS ties the grant to the exact build it was given
                        // to; after reinstalling a differently signed copy the
                        // switch in System Settings stays on but no longer applies.
                        Text(L("ax_stale_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(L("paste_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Text(L("version"))
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary)
                }
                HStack {
                    Text("GitHub")
                    Spacer()
                    Link("github.com/iamzifei/clipstack",
                         destination: URL(string: "https://github.com/iamzifei/clipstack")!)
                        .font(.system(size: 12))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 640)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func recorderRow(_ label: String, _ target: SettingsModel.Target) -> some View {
        HStack {
            Text(label)
            Spacer()
            Button {
                model.beginRecording(target)
            } label: {
                Text(model.recordingTarget == target ? L("hk_recording") : model.displayString(for: target))
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 90)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Owns the (single) settings window. The app is an accessory, so showing
/// the window explicitly activates us to bring it frontmost.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model = SettingsModel()
    private var window: NSWindow?
    /// Polls the Accessibility state while the window is open, so granting
    /// it in System Settings shows up here without clicking back first.
    private var axTimer: Timer?

    override init() {
        super.init()
        // A language switch (here or in the welcome guide) rebuilds the
        // window so every label and the title follow at once.
        NotificationCenter.default.addObserver(forName: AppLanguage.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, let window = self.window else { return }
            self.model.language = AppLanguage.storedChoice ?? "system"
            window.title = L("settings_title")
            window.contentView = NSHostingView(rootView: SettingsView(model: self.model))
        }
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = L("settings_title")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.delegate = self
            w.center()
            window = w
        }
        model.refreshLoginState()
        model.refreshAccessibility()
        // The language may have been changed in the welcome guide while
        // this window was closed (the observer only updates an open window).
        model.language = AppLanguage.storedChoice ?? "system"
        axTimer?.invalidate()
        axTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.model.refreshAccessibility()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Coming back from System Settings after granting Accessibility.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refreshAccessibility()
    }

    func windowWillClose(_ notification: Notification) {
        axTimer?.invalidate()
        axTimer = nil
        if model.recordingTarget != nil {
            model.endRecording()
        }
    }
}
