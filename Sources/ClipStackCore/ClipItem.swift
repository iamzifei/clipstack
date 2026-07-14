import Foundation
import CryptoKit

/// What kind of pasteboard payload a history entry holds.
public enum ClipKind: String, Codable, Equatable {
    case text   // plain text, optionally with RTF/HTML rich flavors
    case image  // a bitmap, persisted as a PNG file next to the history JSON
    case file   // one or more file URLs copied from Finder etc.
}

/// One clipboard history entry.
///
/// Image bytes are NOT stored inside this struct (they would bloat the JSON
/// history file); instead `imageFileName` points to a PNG inside the store's
/// `images/` directory.
public struct ClipItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let kind: ClipKind
    /// Stable content fingerprint used for de-duplication across re-copies.
    public let contentHash: String

    public var plainText: String?
    public var rtfData: Data?
    public var htmlData: Data?

    public var imageFileName: String?
    public var imagePixelWidth: Int?
    public var imagePixelHeight: Int?

    /// Absolute POSIX paths for `.file` entries.
    public var fileURLs: [String]?

    public var createdAt: Date
    public var pinned: Bool
    /// Localized name of the frontmost app when the copy happened.
    public var sourceApp: String?
    /// Approximate payload size in bytes (for display only).
    public var byteSize: Int

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        contentHash: String,
        plainText: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imageFileName: String? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        fileURLs: [String]? = nil,
        createdAt: Date = Date(),
        pinned: Bool = false,
        sourceApp: String? = nil,
        byteSize: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.contentHash = contentHash
        self.plainText = plainText
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageFileName = imageFileName
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.fileURLs = fileURLs
        self.createdAt = createdAt
        self.pinned = pinned
        self.sourceApp = sourceApp
        self.byteSize = byteSize
    }

    /// Single-line summary shown in list rows and the status menu.
    public var previewLine: String {
        switch kind {
        case .text:
            let flattened = (plainText ?? "")
                .replacingOccurrences(of: "\n", with: " ⏎ ")
                .trimmingCharacters(in: .whitespaces)
            return flattened.isEmpty ? L("empty_text") : String(flattened.prefix(90))
        case .image:
            var dims = ""
            if let w = imagePixelWidth, let h = imagePixelHeight { dims = "\(w)×\(h) " }
            return "\(L("kind_image")) \(dims)(\(ByteFormat.string(byteSize)))"
        case .file:
            let names = (fileURLs ?? []).map { URL(fileURLWithPath: $0).lastPathComponent }
            if names.count == 1 { return names[0] }
            return String(format: L("files_count_prefix"), names.count) + names.prefix(3).joined(separator: ", ")
        }
    }

    /// Text used by the switcher's search filter.
    public var searchText: String {
        switch kind {
        case .text: return plainText ?? ""
        case .file: return (fileURLs ?? []).joined(separator: "\n")
        case .image: return "image 图片 \(L("kind_image")) " + (sourceApp ?? "")
        }
    }

    // MARK: content fingerprints

    public static func hashOf(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func hashOfText(_ s: String) -> String { "t-" + hashOf(Data(s.utf8)) }
    public static func hashOfImage(_ d: Data) -> String { "i-" + hashOf(d) }
    public static func hashOfFiles(_ paths: [String]) -> String {
        "f-" + hashOf(Data(paths.joined(separator: "\u{0}").utf8))
    }
}

public enum ByteFormat {
    public static func string(_ n: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }
}
