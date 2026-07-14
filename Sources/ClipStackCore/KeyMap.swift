import Foundation

/// Shared UserDefaults keys.
public enum PrefKey {
    public static let hotKeyCode = "HotKeyKeyCode"                 // switcher panel
    public static let hotKeyMods = "HotKeyModifiers"
    public static let settingsHotKeyCode = "SettingsHotKeyKeyCode" // settings window
    public static let settingsHotKeyMods = "SettingsHotKeyModifiers"
    public static let maxItems = "MaxItems"
}

/// Localized string lookup against the app bundle. Falls back to the key
/// itself when running unbundled (swift run / tests).
public func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Pure keyboard math shared by the hotkey manager, the settings recorder
/// and the status menu: Carbon ↔ Cocoa modifier conversion and key-code
/// display names. Kept AppKit-free so it is unit-testable.
public enum KeyMap {
    // Carbon modifier bits (Carbon.HIToolbox cmdKey/shiftKey/optionKey/controlKey)
    public static let carbonCmd: UInt32 = 0x0100
    public static let carbonShift: UInt32 = 0x0200
    public static let carbonOption: UInt32 = 0x0800
    public static let carbonControl: UInt32 = 0x1000

    // Cocoa NSEvent.ModifierFlags raw bits (stable public constants)
    public static let cocoaShift: UInt = 1 << 17
    public static let cocoaControl: UInt = 1 << 18
    public static let cocoaOption: UInt = 1 << 19
    public static let cocoaCommand: UInt = 1 << 20

    public static func carbonFlags(fromCocoa raw: UInt) -> UInt32 {
        var carbon: UInt32 = 0
        if raw & cocoaCommand != 0 { carbon |= carbonCmd }
        if raw & cocoaShift != 0 { carbon |= carbonShift }
        if raw & cocoaOption != 0 { carbon |= carbonOption }
        if raw & cocoaControl != 0 { carbon |= carbonControl }
        return carbon
    }

    public static func cocoaFlags(fromCarbon carbon: UInt32) -> UInt {
        var raw: UInt = 0
        if carbon & carbonCmd != 0 { raw |= cocoaCommand }
        if carbon & carbonShift != 0 { raw |= cocoaShift }
        if carbon & carbonOption != 0 { raw |= cocoaOption }
        if carbon & carbonControl != 0 { raw |= cocoaControl }
        return raw
    }

    /// Global hotkeys must include ⌘, ⌥ or ⌃ (shift alone would shadow typing).
    public static func hasRequiredModifier(carbon: UInt32) -> Bool {
        carbon & (carbonCmd | carbonOption | carbonControl) != 0
    }

    /// Apple's canonical modifier ordering: ⌃⌥⇧⌘.
    public static func modifierSymbols(carbon: UInt32) -> String {
        var s = ""
        if carbon & carbonControl != 0 { s += "⌃" }
        if carbon & carbonOption != 0 { s += "⌥" }
        if carbon & carbonShift != 0 { s += "⇧" }
        if carbon & carbonCmd != 0 { s += "⌘" }
        return s
    }

    private static let names: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        47: ".", 43: ",", 44: "/", 41: ";", 39: "'", 33: "[", 30: "]", 42: "\\",
        27: "-", 24: "=", 50: "`",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
        117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    public static func keyName(forKeyCode code: Int) -> String {
        names[code] ?? "Key\(code)"
    }

    public static func displayString(keyCode: Int, carbonModifiers: UInt32) -> String {
        modifierSymbols(carbon: carbonModifiers) + keyName(forKeyCode: keyCode)
    }

    /// Character usable as an NSMenuItem key equivalent, or nil for special keys.
    public static func keyEquivalentChar(forKeyCode code: Int) -> String? {
        if code == 49 { return " " }
        guard let name = names[code],
              name.count == 1,
              let scalar = name.unicodeScalars.first, scalar.isASCII else { return nil }
        return name.lowercased()
    }
}
