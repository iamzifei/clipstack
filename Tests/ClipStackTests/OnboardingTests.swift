import XCTest
@testable import ClipStackCore

/// The welcome guide must appear exactly once per guide version: on a fresh
/// install, and once more for people upgrading from before it existed.
final class OnboardingTests: XCTestCase {

    func testShowsWhenNeverSeen() {
        XCTAssertTrue(Onboarding.shouldShow(seenVersion: 0))
    }

    func testHiddenOnceCurrentVersionSeen() {
        XCTAssertFalse(Onboarding.shouldShow(seenVersion: Onboarding.currentVersion))
        XCTAssertFalse(Onboarding.shouldShow(seenVersion: Onboarding.currentVersion + 1), "a newer build's mark also counts")
    }

    func testPageStepsAreClampedToTheGuide() {
        let last = Onboarding.pageCount - 1
        XCTAssertEqual(Onboarding.page(0, step: -1), 0)
        XCTAssertEqual(Onboarding.page(0, step: 1), 1)
        XCTAssertEqual(Onboarding.page(last, step: 1), last)
        XCTAssertEqual(Onboarding.page(99, step: 0), last)
    }
}
