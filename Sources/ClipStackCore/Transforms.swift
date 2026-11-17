import Foundation

/// Text rewrites offered by the switcher's ⌘K transform menu.
///
/// Each case is a pure String -> String function. `available(for:)` returns
/// only the transforms that would actually change the input, so the menu
/// never shows a no-op entry (e.g. "UPPERCASE" on text that already is).
public enum TextTransform: String, CaseIterable {
    case uppercase, lowercase, titleCase, trimWhitespace, joinLines
    case jsonPretty, jsonMinify, urlEncode, urlDecode

    /// Localization key for the menu title.
    public var titleKey: String { "tf_" + rawValue }

    /// Returns the transformed text, or nil when the transform does not apply
    /// (invalid JSON, nothing to decode…) or would leave the text unchanged.
    public func apply(_ text: String) -> String? {
        let out: String?
        switch self {
        case .uppercase:
            out = text.uppercased()
        case .lowercase:
            out = text.lowercased()
        case .titleCase:
            out = text.capitalized
        case .trimWhitespace:
            // Trim each line's trailing spaces plus the whole block's edges —
            // the usual mess left by terminal or PDF copies.
            out = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in
                    var l = Substring(line)
                    while let last = l.last, last == " " || last == "\t" || last == "\r" { l.removeLast() }
                    return String(l)
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .joinLines:
            out = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .jsonPretty:
            out = Self.reserializeJSON(text, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        case .jsonMinify:
            out = Self.reserializeJSON(text, options: [.withoutEscapingSlashes, .sortedKeys])
        case .urlEncode:
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            out = text.addingPercentEncoding(withAllowedCharacters: allowed)
        case .urlDecode:
            out = text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        }
        guard let result = out, result != text, !result.isEmpty else { return nil }
        return result
    }

    /// Transforms that change `text`, in menu order.
    public static func available(for text: String) -> [TextTransform] {
        allCases.filter { t in
            // URL-encoding a multi-paragraph note is never what anyone wants;
            // only offer it for short single-line strings.
            if t == .urlEncode && (text.contains("\n") || text.count > 2_000) { return false }
            // Decoding only makes sense if there is an escape to decode.
            if t == .urlDecode && !text.contains("%") { return false }
            return t.apply(text) != nil
        }
    }

    private static func reserializeJSON(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [Any] || object is [String: Any],
              let outData = try? JSONSerialization.data(withJSONObject: object, options: options)
        else { return nil }
        return String(data: outData, encoding: .utf8)
    }
}

/// Alternate notations for a colour entry (HEX / RGB / HSL), excluding the
/// one the entry is already written in.
public enum ColorTransform {
    public static func alternatives(for text: String) -> [String] {
        guard let color = ContentClassifier.parseColor(text) else { return [] }
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [color.hexString, color.rgbString, color.hslString]
            .filter { $0.lowercased() != current }
    }
}

/// Combines several marked entries into one text payload (⌘M multi-select).
public enum ClipMerge {
    /// Joins entries in the given order with a newline. Text contributes its
    /// plain text, files their paths; images have no textual form and are
    /// skipped. Returns nil if nothing textual is left.
    public static func text(for items: [ClipItem], separator: String = "\n") -> String? {
        let parts: [String] = items.compactMap { item in
            switch item.kind {
            case .text: return item.plainText
            case .file: return item.fileURLs?.joined(separator: "\n")
            case .image: return nil
            }
        }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }
}

public extension ClipItem {
    /// Builds a fresh text entry (used for transform / merge results).
    static func text(_ s: String, sourceApp: String? = "ClipStack") -> ClipItem {
        ClipItem(
            kind: .text,
            contentHash: ClipItem.hashOfText(s),
            plainText: s,
            sourceApp: sourceApp,
            byteSize: s.utf8.count
        )
    }
}
