import XCTest
@testable import ClipStackCore

/// The in-app language choice: nil/"system" follows macOS, an explicit
/// choice wins, and an unsupported system language falls back to English.
final class AppLanguageTests: XCTestCase {

    func testSupportsAtLeastEnglishAndBothChinese() {
        for code in ["en", "zh-Hans", "zh-Hant"] {
            XCTAssertTrue(AppLanguage.supported.contains(code), code)
        }
    }

    func testSystemDefaultMatchesPreferredLanguages() {
        XCTAssertEqual(AppLanguage.resolve(override: nil, preferred: ["zh-Hans-CN", "en-US"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.resolve(override: nil, preferred: ["zh-Hant-TW"]), "zh-Hant")
        XCTAssertEqual(AppLanguage.resolve(override: nil, preferred: ["de-DE"]), "de")
        XCTAssertEqual(AppLanguage.resolve(override: nil, preferred: ["en-AU"]), "en")
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.resolve(override: nil, preferred: ["th-TH"]), "en")
        XCTAssertEqual(AppLanguage.resolve(override: nil, preferred: []), "en")
    }

    func testExplicitChoiceWinsAndUnknownChoiceIsIgnored() {
        XCTAssertEqual(AppLanguage.resolve(override: "zh-Hant", preferred: ["en-US"]), "zh-Hant")
        XCTAssertEqual(AppLanguage.resolve(override: "xx", preferred: ["ja-JP"]), "ja")
    }

    func testEveryLanguageHasANativeName() {
        for code in AppLanguage.supported {
            XCTAssertFalse(AppLanguage.nativeName(code).isEmpty, code)
            XCTAssertNotEqual(AppLanguage.nativeName(code), code, "shows a name, not a code: \(code)")
        }
    }
}
