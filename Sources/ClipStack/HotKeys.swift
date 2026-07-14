import AppKit
import Carbon.HIToolbox
import ClipStackCore

/// Owns the app's two global hotkeys (history switcher + settings window)
/// and reloads them from UserDefaults so the settings panel can rebind
/// them at runtime.
final class HotKeys {
    var openSwitcher: () -> Void = {}
    var openSettings: () -> Void = {}
    private var registeredIDs: [UInt32] = []

    /// Switcher panel combo, default ⇧⌘V.
    static var switcherCombo: (code: Int, mods: Int) {
        let defaults = UserDefaults.standard
        return (
            defaults.object(forKey: PrefKey.hotKeyCode) as? Int ?? kVK_ANSI_V,
            defaults.object(forKey: PrefKey.hotKeyMods) as? Int ?? (cmdKey | shiftKey)
        )
    }

    /// Settings window combo, default ⌘. (Command+Period).
    static var settingsCombo: (code: Int, mods: Int) {
        let defaults = UserDefaults.standard
        return (
            defaults.object(forKey: PrefKey.settingsHotKeyCode) as? Int ?? kVK_ANSI_Period,
            defaults.object(forKey: PrefKey.settingsHotKeyMods) as? Int ?? cmdKey
        )
    }

    /// (Re-)registers both hotkeys from the current defaults.
    func reload() {
        suspend()
        let switcher = Self.switcherCombo
        let switcherID = HotKeyCenter.shared.register(
            keyCode: UInt32(switcher.code),
            carbonModifiers: UInt32(switcher.mods)
        ) { [weak self] in self?.openSwitcher() }
        if switcherID != 0 { registeredIDs.append(switcherID) }

        let settings = Self.settingsCombo
        let settingsID = HotKeyCenter.shared.register(
            keyCode: UInt32(settings.code),
            carbonModifiers: UInt32(settings.mods)
        ) { [weak self] in self?.openSettings() }
        if settingsID != 0 { registeredIDs.append(settingsID) }
    }

    /// Temporarily releases both hotkeys (used while the settings recorder
    /// captures a new combo — otherwise the bound combo never reaches it).
    func suspend() {
        registeredIDs.forEach { HotKeyCenter.shared.unregister(id: $0) }
        registeredIDs = []
    }
}
