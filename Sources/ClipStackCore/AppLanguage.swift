import Foundation

/// In-app language choice, independent of the macOS system language.
///
/// `L()` reads strings from the chosen language's .lproj, so switching takes
/// effect on the next render of each window without a relaunch.
public enum AppLanguage {
    /// Every UI language ClipStack ships, in the order the pickers list them.
    public static let supported = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de"]

    /// Language names written in that language, as macOS shows them.
    public static func nativeName(_ code: String) -> String {
        switch code {
        case "en": return "English"
        case "zh-Hans": return "简体中文"
        case "zh-Hant": return "繁體中文"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "es": return "Español"
        case "fr": return "Français"
        case "de": return "Deutsch"
        default: return code
        }
    }

    /// The language to use: an explicit supported choice, else the first
    /// system language ClipStack supports, else English.
    public static func resolve(override: String?, preferred: [String]) -> String {
        if let override, supported.contains(override) { return override }
        return Bundle.preferredLocalizations(from: supported, forPreferences: preferred)
            .first { supported.contains($0) } ?? "en"
    }

    /// The stored choice; nil = follow the system.
    public static var storedChoice: String? {
        get { UserDefaults.standard.string(forKey: PrefKey.appLanguage) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: PrefKey.appLanguage) }
            else { UserDefaults.standard.removeObject(forKey: PrefKey.appLanguage) }
            cachedBundle = nil
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Posted after the language changes so long-lived windows can rebuild.
    public static let didChange = Notification.Name("ClipStackLanguageDidChange")

    /// The language currently in effect.
    public static var current: String {
        resolve(override: storedChoice, preferred: Locale.preferredLanguages)
    }

    /// Bundle holding the current language's strings (Bundle.main when
    /// running unbundled, where no .lproj exists).
    public static var bundle: Bundle {
        if let cachedBundle { return cachedBundle }
        let b = Bundle.main.path(forResource: current, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        cachedBundle = b
        return b
    }

    private static var cachedBundle: Bundle?
}
