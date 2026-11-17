import Foundation

/// Pure state machine behind the opt-in "hold ⌘, tap V" ring.
///
/// The CGEventTap in the app translates raw events into `Input`s and obeys
/// the returned `Output`. Keeping the logic here (no CoreGraphics) makes the
/// dangerous part — deciding which system-wide keystrokes to swallow —
/// unit-testable. The invariant every rule below protects:
///
///   **The machine only swallows keys while ⌘ is physically held and a ring
///   is in progress; any sign that ⌘ is no longer held ends the ring.**
///
/// If that invariant broke, ordinary typing of "v" (or ⌫ / esc) would be
/// eaten in every app.
public struct RingMachine: Equatable {

    public enum Key: Equatable { case v, delete, escape, other }

    public enum Input: Equatable {
        /// A keyDown. `synthetic` = posted by ClipStack itself (our paste).
        case keyDown(Key, command: Bool, shift: Bool, otherModifiers: Bool, autorepeat: Bool, synthetic: Bool)
        /// Modifier state changed; `command` = is ⌘ still held.
        case flagsChanged(command: Bool)
        /// macOS disabled the tap (timeout / user input). Events may have
        /// been missed, including the ⌘ release.
        case tapDisabled
    }

    public enum Effect: Equatable { case begin, step(Int), delete, cancel, commit }

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

    public private(set) var isActive = false

    public init() {}

    /// `canBegin` is consulted only for a ring-starting ⌘V (history not
    /// empty, ClipStack itself not frontmost, …).
    public mutating func handle(_ input: Input, canBegin: () -> Bool) -> Output {
        switch input {
        case .tapDisabled:
            // We may have missed the ⌘ release: never stay active blind.
            guard isActive else { return .pass }
            isActive = false
            return Output(swallow: false, effect: .cancel)

        case .flagsChanged(let command):
            guard isActive, !command else { return .pass }
            isActive = false
            return Output(swallow: false, effect: .commit)

        case let .keyDown(key, command, shift, otherModifiers, autorepeat, synthetic):
            // Our own posted ⌘V must reach the target app untouched.
            if synthetic { return .pass }

            if isActive {
                // A keyDown without ⌘ means the release was lost somewhere:
                // end the ring and let the key through as normal typing.
                guard command else {
                    isActive = false
                    return Output(swallow: false, effect: .cancel)
                }
                switch key {
                case .v:
                    // Holding V would otherwise race through history at key-
                    // repeat speed; only distinct taps step.
                    if autorepeat { return Output(swallow: true) }
                    return Output(swallow: true, effect: .step(shift ? -1 : 1))
                case .delete:
                    return Output(swallow: true, effect: .delete)
                case .escape:
                    isActive = false
                    return Output(swallow: true, effect: .cancel)
                case .other:
                    // ⌘A / ⌘Return / ⌘S right after ⌘V: the user expects the
                    // paste to happen first. Commit now, hold the key back,
                    // and have the app replay it after the paste.
                    isActive = false
                    return Output(swallow: true, effect: .commit, replay: true)
                }
            }

            // Only a plain, fresh ⌘V starts a ring; ⇧⌘V, ⌥⌘V etc. keep their meaning.
            guard key == .v, command, !shift, !otherModifiers, !autorepeat else { return .pass }
            guard canBegin() else { return .pass }
            isActive = true
            return Output(swallow: true, effect: .begin)
        }
    }
}
