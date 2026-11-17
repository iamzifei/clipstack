import XCTest
@testable import ClipStackCore

/// ⌘K transforms and ⌘M merge. The menu is built from `available(for:)`, so
/// "does not offer a no-op" is as important as "produces the right output".
final class TransformTests: XCTestCase {

    func testCaseTransforms() {
        XCTAssertEqual(TextTransform.uppercase.apply("hello World"), "HELLO WORLD")
        XCTAssertEqual(TextTransform.lowercase.apply("Hello World"), "hello world")
        XCTAssertEqual(TextTransform.titleCase.apply("hello world"), "Hello World")
        XCTAssertNil(TextTransform.uppercase.apply("ALREADY"), "no-op must return nil")
    }

    func testTrimAndJoin() {
        XCTAssertEqual(TextTransform.trimWhitespace.apply("  a  \n b \t\n\n"), "a\n b")
        XCTAssertEqual(TextTransform.joinLines.apply("one\n  two\n\nthree"), "one two three")
        XCTAssertNil(TextTransform.joinLines.apply("single line"))
    }

    func testJSON() {
        XCTAssertEqual(TextTransform.jsonMinify.apply("{ \"b\": 1,\n \"a\": [1, 2] }"), "{\"a\":[1,2],\"b\":1}")
        let pretty = TextTransform.jsonPretty.apply("{\"a\":{\"b\":\"https://x.y/z\"}}")
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\n"))
        XCTAssertTrue(pretty!.contains("https://x.y/z"), "slashes must not be escaped")
        XCTAssertNil(TextTransform.jsonPretty.apply("not json"))
        XCTAssertNil(TextTransform.jsonPretty.apply("42"), "bare scalars are not worth reformatting")
    }

    func testURLCoding() {
        XCTAssertEqual(TextTransform.urlEncode.apply("a b&c=中"), "a%20b%26c%3D%E4%B8%AD")
        XCTAssertEqual(TextTransform.urlDecode.apply("a%20b+c"), "a b c")
    }

    func testAvailableOnlyListsChangingTransforms() {
        let upper = TextTransform.available(for: "HELLO")
        XCTAssertFalse(upper.contains(.uppercase))
        XCTAssertTrue(upper.contains(.lowercase))
        XCTAssertFalse(upper.contains(.urlDecode), "nothing to decode")
        XCTAssertFalse(upper.contains(.jsonPretty))

        let multiline = TextTransform.available(for: "line one\nline two")
        XCTAssertTrue(multiline.contains(.joinLines))
        XCTAssertFalse(multiline.contains(.urlEncode), "multi-line text is never URL-encoded")

        XCTAssertTrue(TextTransform.available(for: "{\"a\":1}").contains(.jsonPretty))
    }

    func testColorAlternativesExcludeCurrentNotation() {
        let alts = ColorTransform.alternatives(for: "#4f8ef7")
        XCTAssertEqual(alts, ["rgb(79, 142, 247)", "hsl(218, 91%, 64%)"])
        XCTAssertEqual(ColorTransform.alternatives(for: "plain text"), [])
    }

    func testEveryTransformHasATitleKey() throws {
        // The menu shows L(titleKey); a missing key would show "tf_xxx".
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/en.lproj/Localizable.strings")
        let strings = try String(contentsOf: url, encoding: .utf8)
        for t in TextTransform.allCases {
            XCTAssertTrue(strings.contains("\"\(t.titleKey)\""), "missing \(t.titleKey)")
        }
    }

    func testMergeKeepsOrderAndSkipsImages() {
        let a = ClipItem.text("first")
        let img = ClipItem(kind: .image, contentHash: "i-1")
        let f = ClipItem(kind: .file, contentHash: "f-1", fileURLs: ["/a", "/b"])
        let c = ClipItem.text("third")
        XCTAssertEqual(ClipMerge.text(for: [c, a]), "third\nfirst")
        XCTAssertEqual(ClipMerge.text(for: [a, img, f]), "first\n/a\n/b")
        XCTAssertNil(ClipMerge.text(for: [img]))
    }
}
