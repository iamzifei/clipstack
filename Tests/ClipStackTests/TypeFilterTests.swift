import XCTest
@testable import ClipStackCore

/// The type filter cycles All → each type that actually occurs → All, so
/// Tab never lands on an empty list.
final class TypeFilterTests: XCTestCase {

    func testAvailableKeepsFixedOrderAndOnlyPresentTypes() {
        let present: Set<ContentType> = [.file, .url, .code]
        XCTAssertEqual(TypeFilter.available(present), [.url, .code, .file])
        XCTAssertEqual(TypeFilter.available([]), [])
    }

    func testCycleForwardWrapsThroughAll() {
        let types: [ContentType] = [.url, .code]
        XCTAssertEqual(TypeFilter.cycle(nil, available: types, step: 1), .url)
        XCTAssertEqual(TypeFilter.cycle(.url, available: types, step: 1), .code)
        XCTAssertEqual(TypeFilter.cycle(.code, available: types, step: 1), nil, "wraps back to All")
    }

    func testCycleBackward() {
        let types: [ContentType] = [.url, .code]
        XCTAssertEqual(TypeFilter.cycle(nil, available: types, step: -1), .code)
        XCTAssertEqual(TypeFilter.cycle(.url, available: types, step: -1), nil)
    }

    func testCycleFromVanishedTypeRestartsFromAll() {
        // The filtered type's last entry was deleted meanwhile.
        XCTAssertEqual(TypeFilter.cycle(.color, available: [.url, .code], step: 1), .url)
    }

    func testCycleWithNothingAvailableStaysAll() {
        XCTAssertNil(TypeFilter.cycle(nil, available: [], step: 1))
        XCTAssertNil(TypeFilter.cycle(.url, available: [], step: -1))
    }

    func testAppearanceModeParsesStoredValueAndDefaultsToSystem() {
        XCTAssertEqual(AppearanceMode(stored: "dark"), .dark)
        XCTAssertEqual(AppearanceMode(stored: "light"), .light)
        XCTAssertEqual(AppearanceMode(stored: nil), .system)
        XCTAssertEqual(AppearanceMode(stored: "bogus"), .system)
    }
}
