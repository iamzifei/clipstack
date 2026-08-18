import XCTest

/// Guards the translation set itself.
///
/// The app ships eight `.lproj` bundles and every user-facing string is looked
/// up by key. A key that exists in English and nowhere else does not fail to
/// build and does not crash — it silently shows the raw key to whoever reads
/// that language. These tests compare the files against each other so that
/// gap is caught here instead of in a screenshot from a German user.
final class LocalizationTests: XCTestCase {

    /// Every language the bundle declares. Kept literal rather than globbed so
    /// that deleting a directory by accident fails the test.
    private let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de"]

    private var resourcesRoot: URL {
        // Tests run from the package, so the source tree is the source of truth;
        // build.sh copies these same files into the .app.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ClipStackTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Resources", isDirectory: true)
    }

    private func keys(of language: String) throws -> Set<String> {
        let url = resourcesRoot
            .appendingPathComponent("\(language).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        var found: Set<String> = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let end = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
            found.insert(String(trimmed[trimmed.index(after: trimmed.startIndex)..<end]))
        }
        return found
    }

    func testEveryLanguageHasEveryKey() throws {
        let english = try keys(of: "en")
        XCTAssertGreaterThan(english.count, 40, "English strings file looks truncated")

        for language in languages where language != "en" {
            let translated = try keys(of: language)
            XCTAssertEqual(
                english.subtracting(translated), [],
                "\(language) is missing keys that English has"
            )
            XCTAssertEqual(
                translated.subtracting(english), [],
                "\(language) has keys English does not — a rename that was only half applied"
            )
        }
    }

    func testNoTranslationWasLeftAsItsKey() throws {
        // A placeholder like "menu_support" = "menu_support"; passes the parity
        // test above while showing a snake_case token in the interface.
        for language in languages {
            let url = resourcesRoot
                .appendingPathComponent("\(language).lproj", isDirectory: true)
                .appendingPathComponent("Localizable.strings")
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") {
                let parts = line.components(separatedBy: "\" = \"")
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \";"))
                XCTAssertNotEqual(value, key, "\(language): \(key) was never translated")
            }
        }
    }

    func testTheSupportLinkIsOfferedInEveryLanguage() throws {
        for language in languages {
            XCTAssertTrue(
                try keys(of: language).contains("menu_support"),
                "\(language) cannot show the Ko-fi item"
            )
        }
    }
}
