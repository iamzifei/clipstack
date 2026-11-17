import XCTest
@testable import ClipStackCore

/// The ⌘V ring swallows system-wide keystrokes, so its failure mode is
/// "the user can no longer type v anywhere". These tests pin the rules that
/// prevent that, including the stuck-state scenarios found in review.
final class RingMachineTests: XCTestCase {

    private var m = RingMachine()

    private func key(_ k: RingMachine.Key, cmd: Bool = true, shift: Bool = false,
                     other: Bool = false, repeat_: Bool = false, synthetic: Bool = false,
                     canBegin: Bool = true) -> RingMachine.Output {
        m.handle(.keyDown(k, command: cmd, shift: shift, otherModifiers: other,
                          autorepeat: repeat_, synthetic: synthetic), canBegin: { canBegin })
    }

    private func flags(cmd: Bool) -> RingMachine.Output {
        m.handle(.flagsChanged(command: cmd), canBegin: { true })
    }

    func testQuickCommandVBeginsThenCommitsOnRelease() {
        XCTAssertEqual(key(.v), .init(swallow: true, effect: .begin))
        XCTAssertTrue(m.isActive)
        XCTAssertEqual(flags(cmd: false), .init(swallow: false, effect: .commit))
        XCTAssertFalse(m.isActive)
    }

    func testTapsStepAndShiftStepsBack() {
        _ = key(.v)
        XCTAssertEqual(key(.v), .init(swallow: true, effect: .step(1)))
        XCTAssertEqual(key(.v, shift: true), .init(swallow: true, effect: .step(-1)))
        XCTAssertEqual(key(.delete), .init(swallow: true, effect: .delete))
    }

    func testEscapeCancels() {
        _ = key(.v)
        XCTAssertEqual(key(.escape), .init(swallow: true, effect: .cancel))
        XCTAssertFalse(m.isActive)
        // ⌘ release afterwards is a no-op, not a second commit.
        XCTAssertEqual(flags(cmd: false), .init(swallow: false))
    }

    func testDoesNotBeginWhenNotAllowed() {
        XCTAssertEqual(key(.v, canBegin: false), .init(swallow: false))
        XCTAssertFalse(m.isActive)
    }

    func testOnlyPlainCommandVBegins() {
        XCTAssertEqual(key(.v, cmd: false), .init(swallow: false), "typing v")
        XCTAssertEqual(key(.v, shift: true), .init(swallow: false), "⇧⌘V belongs to the switcher hotkey")
        XCTAssertEqual(key(.v, other: true), .init(swallow: false), "⌥⌘V")
        XCTAssertEqual(key(.v, repeat_: true), .init(swallow: false))
        XCTAssertEqual(key(.other), .init(swallow: false))
        XCTAssertFalse(m.isActive)
    }

    func testOwnSyntheticPasteAlwaysPasses() {
        _ = key(.v)
        XCTAssertEqual(key(.v, synthetic: true), .init(swallow: false))
        XCTAssertTrue(m.isActive)
    }

    func testAutorepeatDoesNotRaceThroughHistory() {
        _ = key(.v)
        XCTAssertEqual(key(.v, repeat_: true), .init(swallow: true, effect: nil))
    }

    /// ⌘V then ⌘A / ⌘Return / ⌘S: the paste must land BEFORE that key,
    /// so the ring commits now and the key is held back to be replayed.
    func testOtherCommandShortcutCommitsFirstThenReplays() {
        _ = key(.v)
        XCTAssertEqual(key(.other), .init(swallow: true, effect: .commit, replay: true))
        XCTAssertFalse(m.isActive)
        // ⌘ release afterwards is a no-op.
        XCTAssertEqual(flags(cmd: false), .init(swallow: false))
    }

    // MARK: review regressions — the ring must never get stuck

    func testTapDisabledWhileActiveCancels() {
        _ = key(.v)
        XCTAssertEqual(m.handle(.tapDisabled, canBegin: { true }), .init(swallow: false, effect: .cancel))
        XCTAssertFalse(m.isActive)
        // ⌘ release was missed; plain typing must work again.
        XCTAssertEqual(key(.v, cmd: false), .init(swallow: false))
        XCTAssertEqual(key(.delete, cmd: false), .init(swallow: false))
        XCTAssertEqual(key(.escape, cmd: false), .init(swallow: false))
    }

    func testKeyWithoutCommandWhileActiveEndsRingAndPasses() {
        _ = key(.v)
        // ⌘-up never arrived, now the user types a plain "v".
        XCTAssertEqual(key(.v, cmd: false), .init(swallow: false, effect: .cancel))
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(key(.v, cmd: false), .init(swallow: false))
    }

    func testTapDisabledWhenIdleIsNoOp() {
        XCTAssertEqual(m.handle(.tapDisabled, canBegin: { true }), .init(swallow: false))
    }
}
