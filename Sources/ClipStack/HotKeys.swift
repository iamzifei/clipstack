import AppKit
import Carbon.HIToolbox
import ClipStackCore

/// Owns the app's two global hotkeys (history switcher + settings window)
/// and reloads them from UserDefaults so the settings panel can rebind
/// them at runtime.
final class HotKeys {
    var openSwitcher: () -> Void = {}
    var openSettings: () -> Void = {}
    var clearAll: () -> Void = {}
    private var registeredIDs: [UInt32] = []

    /// Switcher panel combo, default ⇧⌘V.
    static var switcherCombo: (code: Int, mods: Int) {
        let defaults = UserDefaults.standard
        return (
            defaults.object(forKey: PrefKey.hotKeyCode) as? Int ?? kVK_ANSI_V,
            defaults.object(forKey: PrefKey.hotKeyMods) as? Int ?? (cmdKey | shiftKey)
        )
    }

    /// Settings window combo, default ⌘, (Command+Comma).
    static var settingsCombo: (code: Int, mods: Int) {
        let defaults = UserDefaults.standard
        return (
            defaults.object(forKey: PrefKey.settingsHotKeyCode) as? Int ?? kVK_ANSI_Comma,
            defaults.object(forKey: PrefKey.settingsHotKeyMods) as? Int ?? cmdKey
        )
    }

    /// Clear-all-history combo, default ⇧⌘⌫ (Command+Shift+Delete).
    static var clearAllCombo: (code: Int, mods: Int) {
        let defaults = UserDefaults.standard
        return (
            defaults.object(forKey: PrefKey.clearAllHotKeyCode) as? Int ?? kVK_Delete,
            defaults.object(forKey: PrefKey.clearAllHotKeyMods) as? Int ?? (cmdKey | shiftKey)
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

        let clear = Self.clearAllCombo
        let clearID = HotKeyCenter.shared.register(
            keyCode: UInt32(clear.code),
            carbonModifiers: UInt32(clear.mods)
        ) { [weak self] in self?.clearAll() }
        if clearID != 0 { registeredIDs.append(clearID) }
    }

    /// Temporarily releases both hotkeys (used while the settings recorder
    /// captures a new combo — otherwise the bound combo never reaches it).
    func suspend() {
        registeredIDs.forEach { HotKeyCenter.shared.unregister(id: $0) }
        registeredIDs = []
    }
}
