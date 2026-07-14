import AppKit
import SwiftUI
import ServiceManagement
import ClipStackCore

/// Backing model for the settings window: launch-at-login toggle plus a
/// click-to-record editor for the two global hotkeys.
final class SettingsModel: ObservableObject {
    enum Target { case switcher, settings }

    @Published var switcherCode: Int
    @Published var switcherMods: Int
    @Published var settingsCode: Int
    @Published var settingsMods: Int
    @Published var launchAtLogin = false
    @Published var loginError: String?
    @Published var recordingTarget: Target?
    @Published var recordHint: String?

    var onHotKeysChanged: () -> Void = {}
    var suspendHotKeys: () -> Void = {}
    private var monitor: Any?

    init() {
        let switcher = HotKeys.switcherCombo
        let settings = HotKeys.settingsCombo
        switcherCode = switcher.code
        switcherMods = switcher.mods
        settingsCode = settings.code
        settingsMods = settings.mods
        refreshLoginState()
    }

    var canToggleLogin: Bool { Bundle.main.bundleIdentifier != nil }

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
        let other = target == .switcher ? (settingsCode, settingsMods) : (switcherCode, switcherMods)
        guard (code, mods) != other else {
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
            }
            Section(L("hotkeys_section")) {
                recorderRow(L("hk_switcher"), .switcher)
                recorderRow(L("hk_settings"), .settings)
                if let hint = model.recordHint {
                    Text(hint).font(.caption).foregroundStyle(.orange)
                }
                Text(L("hk_help"))
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
        .frame(width: 420, height: 330)
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

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if model.recordingTarget != nil {
            model.endRecording()
        }
    }
}
