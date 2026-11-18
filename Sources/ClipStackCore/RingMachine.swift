import Foundation

/// Pure state machine behind the opt-in "hold the modifiers, tap the key"
/// ring (default: hold ⇧⌘, tap V). The combo is user-configurable.
///
/// The CGEventTap in the app translates raw events into `Input`s and obeys
/// the returned `Output`. Keeping the logic here (no CoreGraphics) makes the
/// dangerous part — deciding which system-wide keystrokes to swallow —
/// unit-testable. The invariant every rule below protects:
///
///   **The machine only swallows keys while every modifier of the combo is
///   physically held and a ring is in progress; any sign that one of them is
///   no longer held ends the ring.**
///
/// If that invariant broke, ordinary typing (or ⌫ / esc / arrows) would be
/// eaten in every app.
///
/// Modifiers are Carbon bits (`KeyMap.carbonCmd` …), key codes are macOS
/// virtual key codes, so the machine needs no AppKit / CoreGraphics.
public struct RingMachine: Equatable {

    public enum Input: Equatable {
        /// A keyDown. `synthetic` = posted by ClipStack itself (our paste).
        case keyDown(code: Int, modifiers: UInt32, autorepeat: Bool, synthetic: Bool)
        /// Modifier state changed; `modifiers` = what is held now.
        case flagsChanged(modifiers: UInt32)
        /// macOS disabled the tap (timeout / user input). Events may have
        /// been missed, including the modifier release.
        case tapDisabled
    }

    /// What `canBegin` decides for a ring-starting combo press.
    public enum Begin: Equatable {
        /// Start a ring.
        case ring
        /// Let the keystroke through untouched.
        case pass
        /// Swallow it and run the panel hotkey instead (the ring combo is
        /// also the panel shortcut, and a ring can't start right now).
        case panel
    }

    public enum Effect: Equatable { case begin, step(Int), delete, cancel, commit, panel }

    public struct Output: Equatable {
        /// True = drop the event, false = let it reach the focused app.
        public var swallow: Bool
        public var effect: Effect?
        /// The swallowed event must be re-posted AFTER the effect ran (used
        /// to make ⌘V-then-⌘A paste first, select second).
        public var replay: Bool
        public init(swallow: Bool, effect: Effect? = nil, replay: Bool = false) {
            self.swallow = swallow
            self.effect = effect
            self.replay = replay
        }
        static let pass = Output(swallow: false)
    }

    // Virtual key codes the ring reacts to while active.
    static let deleteCodes: Set<Int> = [51, 117]  // ⌫, ⌦
    static let escapeCode = 53
    static let backCodes: Set<Int> = [123, 126]    // ←, ↑
    static let forwardCodes: Set<Int> = [124, 125] // →, ↓

    /// The four modifier bits we track; anything else (caps lock, fn) is ignored.
    static let trackedMods = KeyMap.carbonCmd | KeyMap.carbonShift | KeyMap.carbonOption | KeyMap.carbonControl

    /// Factory combo: hold ⇧⌘, tap V. Plain ⌘V (the 1.5–1.8 default) is
    /// left to the system paste unless the user records it.
    public static let defaultTriggerCode = 9 // V
    public static let defaultHoldModifiers = KeyMap.carbonCmd | KeyMap.carbonShift

    /// The key tapped to start and step the ring (default V).
    public let triggerCode: Int
    /// The modifiers held for the whole ring (default ⇧⌘).
    public let holdModifiers: UInt32

    public private(set) var isActive = false
    /// After a `.panel` press, key-repeats of a still-held combo are eaten
    /// (the Carbon hotkey it replaces fired once), until a release.
    private var swallowRepeats = false

    /// A combo without ⌘ / ⌥ / ⌃ would make plain typing start a ring that
    /// no modifier release can end, so it falls back to the default. The
    /// Settings recorder never stores one; this guards hand-edited defaults.
    public init(triggerCode: Int, holdModifiers: UInt32) {
        let mods = holdModifiers & Self.trackedMods
        if mods & (KeyMap.carbonCmd | KeyMap.carbonOption | KeyMap.carbonControl) == 0 {
            self.triggerCode = Self.defaultTriggerCode
            self.holdModifiers = Self.defaultHoldModifiers
        } else {
            self.triggerCode = triggerCode
            self.holdModifiers = mods
        }
    }

    private func holdsAll(_ mods: UInt32) -> Bool {
        mods & holdModifiers == holdModifiers
    }

    /// `canBegin` is consulted only for a ring-starting combo press
    /// (history not empty, ClipStack itself not frontmost, …).
    public mutating func handle(_ input: Input, canBegin: () -> Begin) -> Output {
        switch input {
        case .tapDisabled:
            // We may have missed the release: never stay active blind.
            guard isActive else { return .pass }
            isActive = false
            return Output(swallow: false, effect: .cancel)

        case .flagsChanged(let mods):
            if !holdsAll(mods & Self.trackedMods) { swallowRepeats = false }
            guard isActive, !holdsAll(mods & Self.trackedMods) else { return .pass }
            isActive = false
            return Output(swallow: false, effect: .commit)

        case let .keyDown(code, rawMods, autorepeat, synthetic):
            // Our own posted ⌘V must reach the target app untouched.
            if synthetic { return .pass }
            let mods = rawMods & Self.trackedMods

            if swallowRepeats {
                if autorepeat && code == triggerCode && holdsAll(mods) { return Output(swallow: true) }
                swallowRepeats = false
            }

            if isActive {
                // A keyDown without the held modifiers means the release was
                // lost somewhere: end the ring and let the key through.
                guard holdsAll(mods) else {
                    isActive = false
                    return Output(swallow: false, effect: .cancel)
                }
                if code == triggerCode {
                    // Holding the key would otherwise race through history at
                    // key-repeat speed; only distinct taps step.
                    if autorepeat { return Output(swallow: true) }
                    // An extra ⇧ (only possible when ⇧ isn't part of the
                    // combo) steps backwards.
                    let extraShift = mods & ~holdModifiers & KeyMap.carbonShift != 0
                    return Output(swallow: true, effect: .step(extraShift ? -1 : 1))
                }
                if Self.backCodes.contains(code) { return Output(swallow: true, effect: .step(-1)) }
                if Self.forwardCodes.contains(code) { return Output(swallow: true, effect: .step(1)) }
                if Self.deleteCodes.contains(code) { return Output(swallow: true, effect: .delete) }
                if code == Self.escapeCode {
                    isActive = false
                    return Output(swallow: true, effect: .cancel)
                }
                // ⌘A / ⌘Return / ⌘S right after the ring: the user expects the
                // paste to happen first. Commit now, hold the key back, and
                // have the app replay it after the paste.
                isActive = false
                return Output(swallow: true, effect: .commit, replay: true)
            }

            // Only the exact combo starts a ring: with ⌘V as the combo,
            // ⇧⌘V / ⌥⌘V keep their own meaning.
            guard code == triggerCode, mods == holdModifiers, !autorepeat else { return .pass }
            switch canBegin() {
            case .pass: return .pass
            case .panel:
                swallowRepeats = true
                return Output(swallow: true, effect: .panel)
            case .ring:
                isActive = true
                return Output(swallow: true, effect: .begin)
            }
        }
    }
}
