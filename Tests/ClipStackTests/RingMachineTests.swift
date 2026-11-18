import XCTest
@testable import ClipStackCore

/// The ring swallows system-wide keystrokes, so its failure mode is "the
/// user can no longer type v anywhere". These tests pin the rules that
/// prevent that, including the stuck-state scenarios found in review, for
/// both the default ⇧⌘V combo and a recorded plain ⌘V.
final class RingMachineTests: XCTestCase {

    private let cmd = KeyMap.carbonCmd
    private let shift = KeyMap.carbonShift
    private let opt = KeyMap.carbonOption
    private let V = 9, A = 0, delete = 51, escape = 53, left = 123, right = 124

    private var m = RingMachine(triggerCode: RingMachine.defaultTriggerCode,
                                holdModifiers: RingMachine.defaultHoldModifiers)

    private func key(_ code: Int, _ mods: UInt32, repeat_: Bool = false, synthetic: Bool = false,
                     begin: RingMachine.Begin = .ring) -> RingMachine.Output {
        m.handle(.keyDown(code: code, modifiers: mods, autorepeat: repeat_, synthetic: synthetic),
                 canBegin: { begin })
    }

    private func flags(_ mods: UInt32) -> RingMachine.Output {
        m.handle(.flagsChanged(modifiers: mods), canBegin: { .ring })
    }

    // MARK: default combo: hold ⇧⌘, tap V

    func testDefaultComboIsShiftCommandV() {
        XCTAssertEqual(RingMachine.defaultTriggerCode, V)
        XCTAssertEqual(RingMachine.defaultHoldModifiers, cmd | shift)
    }

    func testShiftCommandVBeginsAndCommitsWhenEitherModifierIsReleased() {
        XCTAssertEqual(key(V, cmd | shift), .init(swallow: true, effect: .begin))
        XCTAssertTrue(m.isActive)
        XCTAssertEqual(flags(cmd | shift), .init(swallow: false), "still holding both")
        XCTAssertEqual(flags(cmd), .init(swallow: false, effect: .commit), "⇧ let go first")
        XCTAssertFalse(m.isActive)
    }

    func testPlainCommandVIsLeftToTheSystemByDefault() {
        XCTAssertEqual(key(V, cmd), .init(swallow: false), "⌘V must paste normally")
        XCTAssertEqual(key(V, 0), .init(swallow: false), "typing v")
        XCTAssertEqual(key(V, cmd | shift | opt), .init(swallow: false), "⌥⇧⌘V is not the combo")
        XCTAssertEqual(key(V, cmd | shift, repeat_: true), .init(swallow: false))
        XCTAssertEqual(key(A, cmd | shift), .init(swallow: false))
        XCTAssertFalse(m.isActive)
    }

    func testTapsStepForwardAndArrowsStepBothWays() {
        _ = key(V, cmd | shift)
        XCTAssertEqual(key(V, cmd | shift), .init(swallow: true, effect: .step(1)))
        XCTAssertEqual(key(left, cmd | shift), .init(swallow: true, effect: .step(-1)))
        XCTAssertEqual(key(right, cmd | shift), .init(swallow: true, effect: .step(1)))
        XCTAssertEqual(key(delete, cmd | shift), .init(swallow: true, effect: .delete))
        XCTAssertTrue(m.isActive)
    }

    func testEscapeCancels() {
        _ = key(V, cmd | shift)
        XCTAssertEqual(key(escape, cmd | shift), .init(swallow: true, effect: .cancel))
        XCTAssertFalse(m.isActive)
        // The release afterwards is a no-op, not a second commit.
        XCTAssertEqual(flags(0), .init(swallow: false))
    }

    func testBeginDecisions() {
        XCTAssertEqual(key(V, cmd | shift, begin: .pass), .init(swallow: false))
        XCTAssertFalse(m.isActive)
        // Combo is also the panel shortcut and a ring can't start (empty
        // history, ClipStack focused): swallow and open the panel instead.
        XCTAssertEqual(key(V, cmd | shift, begin: .panel), .init(swallow: true, effect: .panel))
        XCTAssertFalse(m.isActive)
    }

    func testOwnSyntheticPasteAlwaysPasses() {
        _ = key(V, cmd | shift)
        XCTAssertEqual(key(V, cmd, synthetic: true), .init(swallow: false))
        XCTAssertTrue(m.isActive)
    }

    func testAutorepeatDoesNotRaceThroughHistory() {
        _ = key(V, cmd | shift)
        XCTAssertEqual(key(V, cmd | shift, repeat_: true), .init(swallow: true, effect: nil))
    }

    /// Ring then ⌘A / ⌘Return / ⌘S: the paste must land BEFORE that key,
    /// so the ring commits now and the key is held back to be replayed.
    func testOtherShortcutCommitsFirstThenReplays() {
        _ = key(V, cmd | shift)
        XCTAssertEqual(key(A, cmd | shift), .init(swallow: true, effect: .commit, replay: true))
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(flags(0), .init(swallow: false))
    }

    // MARK: a recorded combo: plain ⌘V (the pre-1.9 behaviour)

    func testRecordedCommandVCombo() {
        m = RingMachine(triggerCode: V, holdModifiers: cmd)
        XCTAssertEqual(key(V, cmd | shift), .init(swallow: false), "⇧⌘V keeps opening the panel")
        XCTAssertEqual(key(V, cmd), .init(swallow: true, effect: .begin))
        XCTAssertEqual(key(V, cmd | shift), .init(swallow: true, effect: .step(-1)), "extra ⇧ steps back")
        XCTAssertEqual(key(V, cmd), .init(swallow: true, effect: .step(1)))
        XCTAssertEqual(flags(0), .init(swallow: false, effect: .commit))
    }

    func testCapsLockAndFnBitsAreIgnored() {
        let capsLock: UInt32 = 0x0400
        XCTAssertEqual(key(V, cmd | shift | capsLock), .init(swallow: true, effect: .begin))
    }

    // MARK: review regressions — the ring must never get stuck

    func testHoldingThePanelPressDoesNotLeakRepeats() {
        XCTAssertEqual(key(V, cmd | shift, begin: .panel), .init(swallow: true, effect: .panel))
        XCTAssertEqual(key(V, cmd | shift, repeat_: true), .init(swallow: true), "repeat eaten, like the one-shot hotkey")
        XCTAssertEqual(flags(0), .init(swallow: false))
        XCTAssertEqual(key(V, cmd | shift, repeat_: true), .init(swallow: false), "after release, back to normal")
    }

    func testComboWithoutCommandOptionOrControlFallsBackToDefault() {
        m = RingMachine(triggerCode: V, holdModifiers: 0)
        XCTAssertEqual(key(V, 0), .init(swallow: false), "plain v must never start a ring")
        m = RingMachine(triggerCode: V, holdModifiers: shift)
        XCTAssertEqual(key(V, shift), .init(swallow: false), "⇧V either")
        XCTAssertEqual(m.holdModifiers, RingMachine.defaultHoldModifiers)
    }

    func testTapDisabledWhileActiveCancels() {
        _ = key(V, cmd | shift)
        XCTAssertEqual(m.handle(.tapDisabled, canBegin: { .ring }), .init(swallow: false, effect: .cancel))
        XCTAssertFalse(m.isActive)
        // The release was missed; plain typing must work again.
        XCTAssertEqual(key(V, 0), .init(swallow: false))
        XCTAssertEqual(key(delete, 0), .init(swallow: false))
        XCTAssertEqual(key(escape, 0), .init(swallow: false))
        XCTAssertEqual(key(left, 0), .init(swallow: false))
    }

    func testKeyWithoutTheHeldModifiersEndsRingAndPasses() {
        _ = key(V, cmd | shift)
        // ⇧-up never arrived, now the user types ⌘V.
        XCTAssertEqual(key(V, cmd), .init(swallow: false, effect: .cancel))
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(key(V, 0), .init(swallow: false))
    }

    func testTapDisabledWhenIdleIsNoOp() {
        XCTAssertEqual(m.handle(.tapDisabled, canBegin: { .ring }), .init(swallow: false))
    }
}
