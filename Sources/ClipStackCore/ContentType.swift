import Foundation

/// A finer-grained label than `ClipKind`, inferred from the payload itself.
///
/// `ClipKind` says how the entry is *stored* (text / image / file);
/// `ContentType` says what the text *is* (a link, an e-mail, a colour, code),
/// which drives the tag shown on each row and which transforms are offered.
/// It is computed on the fly and never persisted, so history.json is unchanged.
public enum ContentType: String, Equatable, CaseIterable {
    case url, email, color, code, text, image, file

    /// Short uppercase tag shown in the switcher rows (not localized on
    /// purpose — these are format names, like "PDF", and read the same in
    /// every language).
    public var tag: String {
        switch self {
        case .url: return "URL"
        case .email: return "EMAIL"
        case .color: return "COLOR"
        case .code: return "CODE"
        case .text: return "TEXT"
        case .image: return "IMAGE"
        case .file: return "FILE"
        }
    }
}

/// An sRGB colour parsed out of a clipboard string, components 0...255
/// (alpha 0...1).
public struct ColorValue: Equatable {
    public var red: Int
    public var green: Int
    public var blue: Int
    public var alpha: Double

    public init(red: Int, green: Int, blue: Int, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the colour is not fully opaque.
    public var hexString: String {
        let base = String(format: "#%02X%02X%02X", red, green, blue)
        guard alpha < 1 else { return base }
        return base + String(format: "%02X", Int((alpha * 255).rounded()))
    }

    /// `rgb(r, g, b)`, or `rgba(r, g, b, a)` when not fully opaque.
    public var rgbString: String {
        guard alpha < 1 else { return "rgb(\(red), \(green), \(blue))" }
        return "rgba(\(red), \(green), \(blue), \(Self.trim(alpha)))"
    }

    /// `hsl(h, s%, l%)` with whole-number components (CSS notation).
    public var hslString: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        let l = (maxC + minC) / 2
        var h = 0.0, s = 0.0
        let d = maxC - minC
        if d > 0 {
            s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
            switch maxC {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h *= 60
        }
        let hs = Int(h.rounded()) % 360, ss = Int((s * 100).rounded()), ls = Int((l * 100).rounded())
        guard alpha < 1 else { return "hsl(\(hs), \(ss)%, \(ls)%)" }
        return "hsla(\(hs), \(ss)%, \(ls)%, \(Self.trim(alpha)))"
    }

    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.2f", v)
        // "0.50" -> "0.5", "1.00" -> "1"
        var out = s
        while out.contains(".") && (out.hasSuffix("0") || out.hasSuffix(".")) { out.removeLast() }
        return out
    }
}

/// Pure-string heuristics that decide a text entry's `ContentType`.
public enum ContentClassifier {

    public static func classify(_ raw: String) -> ContentType {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .text }
        // The three "single token" types must not contain inner whitespace;
        // a sentence that merely mentions a link is still TEXT.
        let isSingleToken = text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        if parseColor(text) != nil { return .color }
        if isSingleToken && isURL(text) { return .url }
        if isSingleToken && isEmail(text) { return .email }
        if looksLikeCode(text) { return .code }
        return .text
    }

    // MARK: colour

    /// Parses `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(…)` and `rgba(…)`.
    /// Bare hex without `#` is rejected on purpose: "123456" is far more
    /// often an order number than a colour.
    public static func parseColor(_ raw: String) -> ColorValue? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            let hex = String(text.dropFirst())
            guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            guard isPlausibleHexColor(hex) else { return nil }
            func byte(_ s: Substring) -> Int? { Int(s, radix: 16) }
            switch hex.count {
            case 3:
                let digits = hex.map { String(repeating: String($0), count: 2) }
                guard let r = Int(digits[0], radix: 16), let g = Int(digits[1], radix: 16),
                      let b = Int(digits[2], radix: 16) else { return nil }
                return ColorValue(red: r, green: g, blue: b)
            case 6, 8:
                let chars = Array(hex)
                func pair(_ i: Int) -> Int? { byte(Substring(String(chars[i..<i + 2]))) }
                guard let r = pair(0), let g = pair(2), let b = pair(4) else { return nil }
                var alpha = 1.0
                if hex.count == 8, let a = pair(6) { alpha = Double(a) / 255 }
                return ColorValue(red: r, green: g, blue: b, alpha: alpha)
            default:
                return nil
            }
        }

        let lower = text.lowercased()
        guard lower.hasPrefix("rgb"), lower.hasSuffix(")"),
              let open = lower.firstIndex(of: "(") else { return nil }
        let name = lower[..<open]
        guard name == "rgb" || name == "rgba" else { return nil }
        let inner = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let comps = parts.prefix(3).compactMap { Int($0) }
        guard comps.count == 3, comps.allSatisfy({ (0...255).contains($0) }) else { return nil }
        var alpha = 1.0
        if parts.count == 4 {
            guard let a = Double(parts[3]), (0...1).contains(a) else { return nil }
            alpha = a
        }
        return ColorValue(red: comps[0], green: comps[1], blue: comps[2], alpha: alpha)
    }

    /// "#123" / "#123456" are issue and PR numbers far more often than
    /// colours, and "#bad" / "#add" are hashtags. Accept all-digit or
    /// all-letter hex only when every character is the same (#000, #fff,
    /// #333333); mixed letters and digits (#f0a, #4F8EF7) always pass. Six-
    /// or eight-digit all-letter values (#facade) are accepted: too rare as
    /// words to be worth excluding.
    private static func isPlausibleHexColor(_ hex: String) -> Bool {
        let core = hex.count == 8 ? String(hex.prefix(6)) : hex
        let allSame = Set(core.lowercased()).count == 1
        let allDigits = core.allSatisfy(\.isNumber)
        let allLetters = core.allSatisfy(\.isLetter)
        if allDigits { return allSame }
        if allLetters && core.count == 3 { return allSame }
        return true
    }

    // MARK: link / e-mail

    static func isURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("www.") && lower.count > 5 { return true }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https", "ftp":
            return url.host?.isEmpty == false
        case "file", "mailto", "ssh", "git":
            return true
        default:
            return false
        }
    }

    static func isEmail(_ text: String) -> Bool {
        text.range(
            of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#,
            options: .regularExpression
        ) != nil
    }

    // MARK: code

    /// Line-start commands that make a single line read as a shell command.
    /// Deliberately excludes commands that are also everyday English verbs
    /// or nouns ("open", "make", "go", "cat", "echo", "export") — "open the
    /// door" must stay TEXT.
    private static let shellCommands: Set<String> = [
        "$", "npm", "npx", "pnpm", "yarn", "bun", "git", "curl", "wget", "brew", "cd", "ls",
        "sudo", "python", "python3", "pip", "pip3", "swift", "swiftc", "cargo", "docker",
        "kubectl", "ssh", "scp", "rm", "mv", "cp", "mkdir", "chmod", "chown", "defaults",
        "vercel", "gh", "node", "deno", "xcrun", "grep", "launchctl", "pbcopy", "pbpaste",
    ]

    /// Symbol- or syntax-anchored patterns that are convincing on their own,
    /// even in a one-line snippet. Case-sensitive on purpose.
    private static let strongPatterns: [String] = [
        #"^\s*(func|def|fn)\s+\w+\s*[(<]"#,
        #"^\s*(class|struct|enum|interface|impl|protocol)\s+\w+[^\n]*[{:(]\s*$"#,
        #"^\s*(let|const|var)\s+\w+\s*(:[^=]+)?=\s*\S"#,
        // `import Foundation`, `import os.path`, `import foo;` — but not
        // "import duties" (lowercase single word reads as English).
        #"^\s*import\s+([A-Z][\w.]*|[\w]+\.[\w.]+|\w+\s*;)\s*$"#,
        // A bare call: `print("hi")`, `console.log(x);`, `foo.bar(1, 2)`.
        #"^\s*[A-Za-z_][\w.]*\([^()]*\)\s*;?\s*$"#,
        #"^\s*import\s+.*\s+from\s+['"]"#,
        #"^\s*from\s+[\w.]+\s+import\s+\w"#,
        #"^\s*#include\s*[<"]"#,
        #"^\s*using\s+[\w.]+\s*;\s*$"#,
        #"\w\s*=>\s*[\w{(]"#,
        #";\s*$"#,
        #"^\s*</?[a-zA-Z][\w-]*(\s[^>]*)?>"#,
        #"^\s*(SELECT\s.+\sFROM\s|INSERT\s+INTO\s|UPDATE\s+\w+\s+SET\s|DELETE\s+FROM\s|CREATE\s+TABLE\s|ALTER\s+TABLE\s)"#,
    ]

    /// Weaker hints that only count in multi-line snippets, where two or
    /// more of them together are rarely prose.
    private static let weakPatterns: [String] = [
        #"^\s*(return|if|for|while|switch|guard)\b.*[({]\s*$"#,
        #"^\s*[})\]];?,?\s*$"#,
        #"->\s*\w|::|&&|\|\||!==|==="#,
        #"^\s*(//|#!|/\*)"#,
        #"\w\(.*\)\s*[{;]?\s*$"#,
    ]

    static func looksLikeCode(_ text: String) -> Bool {
        if isJSONContainer(text) { return true }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        func matches(_ line: String, _ patterns: [String]) -> Bool {
            patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
        }
        if lines.count == 1 {
            let line = lines[0].trimmingCharacters(in: .whitespaces)
            // Prose sentences end with a full stop; mixed Chinese is prose.
            if line.hasSuffix(".") || line.hasSuffix("。") || containsCJK(line) {
                return false
            }
            let words = line.split(separator: " ").map(String.init)
            if words.count >= 2, shellCommands.contains(words[0]),
               looksLikeShellArgument(words[1]) || line.range(of: #"[-/~=@$|>]"#, options: .regularExpression) != nil {
                return true
            }
            return matches(line, strongPatterns)
        }
        var score = 0
        for line in lines.prefix(80) {
            if matches(line, strongPatterns) {
                score += 2
            } else if matches(line, weakPatterns) {
                score += 1
            }
        }
        return score >= 2
    }

    /// Subcommands that make "git push" / "npm install" read as a command
    /// even without flags or paths ("git is hard" stays prose).
    private static let shellSubcommands: Set<String> = [
        "install", "i", "add", "remove", "run", "exec", "push", "pull", "clone", "commit",
        "checkout", "switch", "status", "log", "diff", "fetch", "merge", "rebase", "build",
        "test", "init", "update", "upgrade", "list", "ls", "start", "stop", "restart", "ps",
        "logs", "deploy", "env", "link", "uninstall", "services", "read", "write", "delete",
        "get", "apply", "describe", "version", "dev", "publish",
    ]

    private static func looksLikeShellArgument(_ word: String) -> Bool {
        shellSubcommands.contains(word) || word.hasPrefix("-") || word.contains("/")
            || word.contains(".") || word.hasPrefix("~")
    }

    /// A JSON object, or an array holding at least two values or any
    /// container. `[1]` / `[2024]` are citations, not data.
    private static func isJSONContainer(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[",
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        if object is [String: Any] { return true }
        guard let array = object as? [Any] else { return false }
        return array.count >= 2 || array.contains { $0 is [Any] || $0 is [String: Any] }
    }

    private static func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
    }
}

public extension ClipItem {
    /// What this entry looks like — see `ContentType`.
    var contentType: ContentType {
        switch kind {
        case .image: return .image
        case .file: return .file
        case .text: return ContentClassifier.classify(plainText ?? "")
        }
    }

    /// Parsed colour when `contentType == .color`.
    var colorValue: ColorValue? {
        guard kind == .text, let text = plainText else { return nil }
        return ContentClassifier.parseColor(text)
    }
}
