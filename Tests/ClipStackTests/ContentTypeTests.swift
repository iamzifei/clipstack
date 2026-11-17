import XCTest
@testable import ClipStackCore

/// Content-type tagging: what each row's URL / EMAIL / COLOR / CODE / TEXT
/// tag says. False positives matter more than misses here — tagging a
/// sentence as CODE is visible noise in every row.
final class ContentTypeTests: XCTestCase {

    private func type(_ s: String) -> ContentType { ContentClassifier.classify(s) }

    func testURLs() {
        XCTAssertEqual(type("https://github.com/iamzifei/clipstack/releases"), .url)
        XCTAssertEqual(type("  http://example.com  \n"), .url)
        XCTAssertEqual(type("www.example.com"), .url)
        // A sentence containing a link is still prose.
        XCTAssertEqual(type("see https://example.com for details"), .text)
        // Scheme without host is not a link.
        XCTAssertEqual(type("https://"), .text)
    }

    func testEmail() {
        XCTAssertEqual(type("support@getclipstack.app"), .email)
        XCTAssertEqual(type("not an @ email"), .text)
    }

    func testColors() {
        XCTAssertEqual(type("#4F8EF7"), .color)
        XCTAssertEqual(type("#fff"), .color)
        XCTAssertEqual(type("#4F8EF780"), .color)
        XCTAssertEqual(type("rgb(79, 142, 247)"), .color)
        XCTAssertEqual(type("rgba(0,0,0,0.5)"), .color)
        // Bare digits are order numbers, not colours.
        XCTAssertNotEqual(type("123456"), .color)
        XCTAssertNotEqual(type("#12345"), .color)
        XCTAssertNotEqual(type("rgb(300, 0, 0)"), .color)
    }

    func testCode() {
        XCTAssertEqual(type("npm install -g agent-desktop@latest"), .code)
        XCTAssertEqual(type("func greet(name: String) -> String {\n    return \"hi \\(name)\"\n}"), .code)
        XCTAssertEqual(type("const x = 1;\nconsole.log(x);"), .code)
        XCTAssertEqual(type("SELECT * FROM users WHERE id = 1"), .code)
        XCTAssertEqual(type("{\"name\":\"clipstack\",\"version\":\"1.5.0\"}"), .code)
        XCTAssertEqual(type("[1, 2, 3]"), .code)
        XCTAssertEqual(type("[draft] notes for Monday"), .text, "brackets alone are not JSON")
    }

    func testProseStaysText() {
        XCTAssertEqual(type("Join Zoom meeting at 3pm tomorrow."), .text)
        XCTAssertEqual(type("let me know if that works"), .text)
        XCTAssertEqual(type("第一行\n第二行，这是普通中文。"), .text)
        XCTAssertEqual(type("Hello; this is one clause.\nAnd another line here."), .text)
        // A single word that happens to be a command name.
        XCTAssertEqual(type("git"), .text)
    }

    /// False positives found in review (2026-11-18): each of these was
    /// tagged COLOR or CODE before the classifier was tightened.
    func testReviewFalsePositivesStayText() {
        for s in ["#123", "#404", "#123456", "#bad", "#add"] {
            XCTAssertNotEqual(type(s), .color, "\(s) is an issue number / hashtag, not a colour")
        }
        for s in ["open the door", "make sure to reply", "go home", "cat is cute",
                  "If so:", "if so:", "For example:", "from now on we ship weekly",
                  "using this approach works", "class notes tomorrow",
                  "A -> B", "x && y", "UPDATE 3 files", "[1]", "[2024]", "open 一下",
                  "export the report to PDF"] {
            XCTAssertNotEqual(type(s), .code, "\(s) is prose, not code")
        }
        // …while real colours / code of the same shapes still classify.
        XCTAssertEqual(type("#fff"), .color)
        XCTAssertEqual(type("#000"), .color)
        XCTAssertEqual(type("#f0a"), .color)
        XCTAssertEqual(type("#000000"), .color)
        XCTAssertEqual(type("import Foundation"), .code)
        XCTAssertEqual(type("UPDATE users SET name = 'x' WHERE id = 1"), .code)
        XCTAssertEqual(type("[1, 2, 3]"), .code)
        XCTAssertEqual(type("git push origin main"), .code)

        // Second review round.
        for s in ["import duties", "python is great", "git is hard", "brew a coffee", "defaults to 5"] {
            XCTAssertNotEqual(type(s), .code, "\(s) is prose, not code")
        }
        XCTAssertEqual(type("console.log(\"x\")"), .code)
        XCTAssertEqual(type("print(\"hi\")"), .code)
        XCTAssertEqual(type("cd ~/Dev/clipstack"), .code)
        XCTAssertEqual(type("def f(x):\n    return x"), .code)
    }

    func testItemKindsMapDirectly() {
        let image = ClipItem(kind: .image, contentHash: "i-x")
        let file = ClipItem(kind: .file, contentHash: "f-x", fileURLs: ["/tmp/a"])
        XCTAssertEqual(image.contentType, .image)
        XCTAssertEqual(file.contentType, .file)
        XCTAssertEqual(ClipItem.text("#000").contentType, .color)
    }

    func testColorFormats() throws {
        let c = try XCTUnwrap(ContentClassifier.parseColor("#4F8EF7"))
        XCTAssertEqual(c, ColorValue(red: 79, green: 142, blue: 247))
        XCTAssertEqual(c.hexString, "#4F8EF7")
        XCTAssertEqual(c.rgbString, "rgb(79, 142, 247)")
        XCTAssertEqual(c.hslString, "hsl(218, 91%, 64%)")

        let short = try XCTUnwrap(ContentClassifier.parseColor("#f0a"))
        XCTAssertEqual(short.hexString, "#FF00AA")

        let translucent = try XCTUnwrap(ContentClassifier.parseColor("rgba(0, 0, 0, 0.5)"))
        XCTAssertEqual(translucent.rgbString, "rgba(0, 0, 0, 0.5)")
        XCTAssertEqual(translucent.hexString, "#00000080")
        XCTAssertEqual(ColorValue(red: 255, green: 255, blue: 255).hslString, "hsl(0, 0%, 100%)")
    }
}
