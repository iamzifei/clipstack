import XCTest
@testable import ClipStackCore

final class KeyMapTests: XCTestCase {
    func testDisplayString() {
        XCTAssertEqual(
            KeyMap.displayString(keyCode: 9, carbonModifiers: KeyMap.carbonCmd | KeyMap.carbonShift),
            "⇧⌘V"
        )
        XCTAssertEqual(KeyMap.displayString(keyCode: 47, carbonModifiers: KeyMap.carbonCmd), "⌘.")
        XCTAssertEqual(
            KeyMap.displayString(keyCode: 126, carbonModifiers: KeyMap.carbonControl | KeyMap.carbonOption),
            "⌃⌥↑"
        )
    }

    func testCarbonCocoaRoundtrip() {
        let cocoa = KeyMap.cocoaCommand | KeyMap.cocoaShift
        let carbon = KeyMap.carbonFlags(fromCocoa: cocoa)
        XCTAssertEqual(carbon, KeyMap.carbonCmd | KeyMap.carbonShift)
        XCTAssertEqual(carbon, 768, "⇧⌘ must match the Carbon cmdKey|shiftKey value")
        XCTAssertEqual(KeyMap.cocoaFlags(fromCarbon: carbon), cocoa)

        let all = KeyMap.carbonCmd | KeyMap.carbonShift | KeyMap.carbonOption | KeyMap.carbonControl
        XCTAssertEqual(KeyMap.carbonFlags(fromCocoa: KeyMap.cocoaFlags(fromCarbon: all)), all)
    }

    func testRequiredModifier() {
        XCTAssertTrue(KeyMap.hasRequiredModifier(carbon: KeyMap.carbonCmd))
        XCTAssertTrue(KeyMap.hasRequiredModifier(carbon: KeyMap.carbonOption))
        XCTAssertTrue(KeyMap.hasRequiredModifier(carbon: KeyMap.carbonControl | KeyMap.carbonShift))
        XCTAssertFalse(KeyMap.hasRequiredModifier(carbon: KeyMap.carbonShift), "shift alone is not allowed")
        XCTAssertFalse(KeyMap.hasRequiredModifier(carbon: 0))
    }

    func testKeyNames() {
        XCTAssertEqual(KeyMap.keyName(forKeyCode: 9), "V")
        XCTAssertEqual(KeyMap.keyName(forKeyCode: 47), ".")
        XCTAssertEqual(KeyMap.keyName(forKeyCode: 49), "Space")
        XCTAssertEqual(KeyMap.keyName(forKeyCode: 999), "Key999")
    }

    func testKeyEquivalentChar() {
        XCTAssertEqual(KeyMap.keyEquivalentChar(forKeyCode: 9), "v")
        XCTAssertEqual(KeyMap.keyEquivalentChar(forKeyCode: 47), ".")
        XCTAssertEqual(KeyMap.keyEquivalentChar(forKeyCode: 49), " ")
        XCTAssertNil(KeyMap.keyEquivalentChar(forKeyCode: 123), "arrow keys have no menu key equivalent")
        XCTAssertNil(KeyMap.keyEquivalentChar(forKeyCode: 122), "F-keys have no menu key equivalent")
        XCTAssertNil(KeyMap.keyEquivalentChar(forKeyCode: 999))
    }

    func testModifierSymbolOrderIsAppleCanonical() {
        let all = KeyMap.carbonCmd | KeyMap.carbonShift | KeyMap.carbonOption | KeyMap.carbonControl
        XCTAssertEqual(KeyMap.modifierSymbols(carbon: all), "⌃⌥⇧⌘")
    }
}
