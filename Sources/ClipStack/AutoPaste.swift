import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipStackCore

/// Opt-in paste automation. Everything in this file needs the Accessibility
/// permission and is dormant unless the user turns one of the two settings
/// on — by default ClipStack still asks for no permissions at all.
enum Accessibility {
    /// True when macOS lets us post synthetic key events / install event taps.
    /// With `prompt`, macOS shows its "allow in System Settings" dialog the
    /// first time it is asked.
    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Paster {
    /// Tag written into our synthetic events so the ⌘V ring's event tap can
    /// recognise (and let through) the paste we post ourselves.
    static let syntheticMarker: Int64 = 0x434C_5053 // "CLPS"

    /// Brings `app` forward and sends it ⌘V once it really is frontmost.
    /// Activation is asynchronous, so poll (≤0.5s) instead of trusting a
    /// fixed delay; if `app` never comes forward (it quit, the user switched
    /// away) nothing is posted — a missing paste beats one in the wrong app.
    static func paste(into app: NSRunningApplication) {
        guard Accessibility.isTrusted(), !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        app.activate()
        func attempt(_ remaining: Int) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                // Small settle delay so the app's key window is ready.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { postCommandV() }
            } else if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { attempt(remaining - 1) }
            }
        }
        attempt(25)
    }

    /// Posts ⌘V to whatever app is frontmost right now (the ⌘V ring: the
    /// target never lost focus). Synchronous so a key replayed right after
    /// it is guaranteed to arrive second.
    static func postCommandV() {
        guard Accessibility.isTrusted() else { return }
        // A private source keeps any modifier the user is still physically
        // holding from leaking into our ⌘V (e.g. ⇧ turning it into ⇧⌘V).
        let source = CGEventSource(stateID: .privateState)
        let v = CGKeyCode(kVK_ANSI_V)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

/// "Hold the modifiers, tap the key" history cycling (default hold ⇧⌘,
/// tap V), modelled on ⌘Tab. The combo is recorded in Settings.
///
/// This class only owns the CGEventTap plumbing; every decision about which
/// keystrokes to swallow lives in `RingMachine` (ClipStackCore, unit-tested):
///   1st combo press        → swallowed; the ring opens on the newest entry
///   key again (mods held)  → next entry;  ← / ↑ previous, → / ↓ next
///   ⌫ / esc                → delete highlighted entry / cancel
///   release a modifier     → paste the highlighted entry into the frontmost app
///
/// If ClipStack ever stalls, macOS disables the tap on timeout; the machine
/// then cancels any ring in progress and the keys fall back to their normal
/// meaning until the tap is re-enabled.
final class CmdVRing {
    /// Driven on the main thread (the tap's run-loop source lives there).
    /// `immediate` is true when a held-back key will be replayed right after
    /// a commit, so the paste must be posted synchronously, before it.
    var handler: ((RingMachine.Effect, _ immediate: Bool) -> Void)?
    /// Asked on the first combo press (history empty, ClipStack itself
    /// frontmost, …).
    var canBegin: (() -> RingMachine.Begin)?
    /// Called whenever the tap comes or goes, so the panel hotkey can step
    /// aside while the ring owns a shared combo.
    var onInstalledChange: (() -> Void)?

    private var machine = RingMachine(triggerCode: RingMachine.defaultTriggerCode,
                                      holdModifiers: RingMachine.defaultHoldModifiers)
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    /// While installed: notices Accessibility being revoked (the tap then
    /// goes silent without telling us) so the panel hotkey comes back.
    private var healthTimer: Timer?

    /// True while the event tap is live (enabled AND Accessibility granted).
    var isInstalled: Bool { tap != nil }

    /// The combo currently in effect (stored in UserDefaults, default ⇧⌘V).
    static var combo: (code: Int, mods: Int) {
        let defaults = UserDefaults.standard
        return (
            defaults.object(forKey: PrefKey.ringHotKeyCode) as? Int ?? RingMachine.defaultTriggerCode,
            defaults.object(forKey: PrefKey.ringHotKeyMods) as? Int ?? Int(RingMachine.defaultHoldModifiers)
        )
    }

    /// Re-reads the combo. An open ring is cancelled first so a half-held
    /// old combo can never leave keys swallowed.
    func reloadCombo() {
        if let effect = machine.handle(.tapDisabled, canBegin: { .pass }).effect {
            handler?(effect, false)
        }
        let c = Self.combo
        machine = RingMachine(triggerCode: c.code, holdModifiers: UInt32(c.mods))
    }

    /// Installs the tap, or keeps retrying every 2s until Accessibility is
    /// granted (the user is typically in System Settings right now).
    func enable() {
        reloadCombo()
        guard tap == nil else { return }
        if install() { onInstalledChange?(); return }
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.install() {
                t.invalidate()
                self.retryTimer = nil
                self.onInstalledChange?()
            }
        }
    }

    func disable() {
        retryTimer?.invalidate()
        retryTimer = nil
        healthTimer?.invalidate()
        healthTimer = nil
        let wasInstalled = tap != nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        // Treat teardown like a lost tap so an open ring is cancelled.
        if let effect = machine.handle(.tapDisabled, canBegin: { .pass }).effect {
            handler?(effect, false)
        }
        if wasInstalled { onInstalledChange?() }
    }

    private func install() -> Bool {
        guard Accessibility.isTrusted() else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let ring = Unmanaged<CmdVRing>.fromOpaque(userInfo).takeUnretainedValue()
                return ring.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = src
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, !Accessibility.isTrusted() else { return }
            // Revoked: tear down (re-registers the Carbon panel hotkey via
            // onInstalledChange) and wait for it to be granted again.
            self.disable()
            self.enable()
        }
        return true
    }

    /// CGEventFlags → the Carbon modifier bits RingMachine works in.
    private static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.maskCommand) { mods |= KeyMap.carbonCmd }
        if flags.contains(.maskShift) { mods |= KeyMap.carbonShift }
        if flags.contains(.maskAlternate) { mods |= KeyMap.carbonOption }
        if flags.contains(.maskControl) { mods |= KeyMap.carbonControl }
        return mods
    }

    /// Translates a raw event into a `RingMachine.Input`, then obeys the output.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: RingMachine.Input
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            input = .tapDisabled
        case .flagsChanged:
            input = .flagsChanged(modifiers: Self.carbonModifiers(event.flags))
        case .keyDown:
            input = .keyDown(
                code: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: Self.carbonModifiers(event.flags),
                autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                synthetic: event.getIntegerValueField(.eventSourceUserData) == Paster.syntheticMarker
            )
        default:
            return Unmanaged.passUnretained(event)
        }

        let output = machine.handle(input) { [weak self] in self?.canBegin?() ?? .pass }
        if let effect = output.effect { handler?(effect, output.replay) }
        if output.replay, let copy = event.copy() {
            // Re-post the held-back key (e.g. ⌘A) after our ⌘V. Marked as
            // synthetic so this tap lets it through untouched.
            copy.setIntegerValueField(.eventSourceUserData, value: Paster.syntheticMarker)
            copy.post(tap: .cghidEventTap)
        }
        return output.swallow ? nil : Unmanaged.passUnretained(event)
    }
}
